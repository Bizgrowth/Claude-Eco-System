// Builds data/github.json from the GitHub API. Run by the scheduled workflow.
// Needs GH_TOKEN (read access to repos/issues/PRs). Node 20+.
import { readFile, writeFile } from "node:fs/promises";

const cfg = JSON.parse(await readFile(new URL("../data/config.json", import.meta.url)));
const token = process.env.GH_TOKEN;
if (!token) throw new Error("GH_TOKEN is not set");
const H = { Authorization: `Bearer ${token}`, Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28" };

async function gh(path) {
  const r = await fetch(`https://api.github.com${path}`, { headers: H });
  if (!r.ok) throw new Error(`${r.status} ${path}`);
  return r.json();
}
// List every repo the token can see (all pages), then keep the ones we want and count what we skip.
const listBase = cfg.ownerType === "user" ? "/user/repos?affiliation=owner,collaborator,organization_member&sort=pushed" : `/orgs/${cfg.owner}/repos?sort=pushed`;
let all = [];
for (let page = 1; page < 20; page++) {
  const batch = await gh(`${listBase}&per_page=100&page=${page}`);
  all = all.concat(batch);
  if (batch.length < 100) break;
}
const owners = (cfg.owners?.length ? cfg.owners : [cfg.owner]).map((o) => o.toLowerCase());
const skipped = { archived: 0, excluded: 0, otherOwners: {} };
const repos = all.filter((r) => {
  const o = r.owner.login.toLowerCase();
  if (!owners.includes(o)) { skipped.otherOwners[r.owner.login] = (skipped.otherOwners[r.owner.login] || 0) + 1; return false; }
  if (r.archived && !cfg.includeArchived) { skipped.archived++; return false; }
  if (cfg.excludeRepos.includes(r.name)) { skipped.excluded++; return false; }
  return true;
});
console.log(`Token can see ${all.length} repos; keeping ${repos.length}; skipped:`, JSON.stringify(skipped));

const out = [];
for (const r of repos) {
  const [issues, prs] = await Promise.all([
    gh(`/repos/${r.full_name}/issues?state=open&per_page=50`).catch(() => []),
    gh(`/repos/${r.full_name}/pulls?state=open&per_page=50`).catch(() => []),
  ]);
  const realIssues = issues.filter((i) => !i.pull_request);
  const labelOf = (i) => i.labels.map((l) => l.name.toLowerCase());
  out.push({
    name: r.name, url: r.html_url, description: r.description, private: r.private,
    pushedAt: r.pushed_at, defaultBranch: r.default_branch,
    openIssues: realIssues.length, openPRs: prs.length,
    priorityItems: realIssues
      .filter((i) => labelOf(i).some((l) => cfg.priorityLabels.includes(l)))
      .map((i) => ({ title: i.title, url: i.html_url, number: i.number })),
    prs: prs.slice(0, 5).map((p) => ({ title: p.title, url: p.html_url, number: p.number, draft: p.draft })),
  });
}
// Optional: GitHub Projects (v2) boards. Needs a token with read:project (classic) — GITHUB_TOKEN can't read these.
let projects = [];
if (cfg.projects?.enabled) {
  const root = cfg.ownerType === "user" ? "user" : "organization";
  const q = `query($login:String!){ ${root}(login:$login){ projectsV2(first:20){ nodes{ title url closed
    items(first:100){ nodes{ content{ ... on Issue{title url} ... on PullRequest{title url} ... on DraftIssue{title} }
      fieldValueByName(name:"Status"){ ... on ProjectV2ItemFieldSingleSelectValue{ name } } } } } } } }`;
  try {
    const r = await fetch("https://api.github.com/graphql", { method: "POST", headers: H, body: JSON.stringify({ query: q, variables: { login: cfg.owner } }) });
    const j = await r.json();
    if (j.errors) throw new Error(j.errors[0].message);
    projects = j.data[root].projectsV2.nodes.map((p) => ({ title: p.title, url: p.url, closed: p.closed,
      items: p.items.nodes.map((n) => ({ title: n.content?.title ?? "(untitled)", url: n.content?.url ?? null, status: n.fieldValueByName?.name ?? null })) }));
  } catch (e) { console.warn("Projects skipped:", e.message); }
}
const payload = JSON.stringify({ generatedAt: new Date().toISOString(), total: all.length, skipped, repos: out, projects }, null, 1);
// Pages sites are public, so private data goes to the private sync repo (DATA_REPO), not into this repo.
if (process.env.DATA_REPO) {
  const url = `https://api.github.com/repos/${process.env.DATA_REPO}/contents/github.json`;
  const cur = await fetch(url, { headers: H });
  const sha = cur.ok ? (await cur.json()).sha : undefined;
  const put = await fetch(url, { method: "PUT", headers: H, body: JSON.stringify({ message: "chore: refresh dashboard data", content: Buffer.from(payload).toString("base64"), sha }) });
  if (!put.ok) throw new Error(`Could not write github.json to ${process.env.DATA_REPO}: ${put.status}`);
} else {
  await writeFile(new URL("../data/github.json", import.meta.url), payload); // local testing only
}
console.log(`Wrote ${out.length} repos`);
