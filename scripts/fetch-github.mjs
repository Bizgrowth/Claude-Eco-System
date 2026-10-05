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
const base = cfg.ownerType === "user" ? `/users/${cfg.owner}` : `/orgs/${cfg.owner}`;
const repos = (await gh(`${base}/repos?per_page=100&sort=pushed`))
  .filter((r) => (cfg.includeArchived || !r.archived) && !cfg.excludeRepos.includes(r.name));

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
await writeFile(new URL("../data/github.json", import.meta.url), JSON.stringify({ generatedAt: new Date().toISOString(), repos: out, projects }, null, 1));
console.log(`Wrote ${out.length} repos`);
