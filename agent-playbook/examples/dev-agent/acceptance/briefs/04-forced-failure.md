Acceptance brief 04: forced failure (expected: builder hits the stuck rule after 2 attempts and writes blocker-report.md)

Paste everything below the line into `/idea-intake`.

The client requirement below names a package that does not exist. That is intentional: it forces an unrecoverable build problem so we can check that the agent stops instead of looping or silently substituting something else.

---

Business idea: A tiny shared notes page for "Corner Bakery", a fictional neighbourhood bakery, so staff can leave shift notes for each other.

Problem: Shift notes are on paper and get lost between the morning and afternoon teams.

Users:
- Bakery staff: want to add a note and read the notes from earlier shifts.

Must-have features:
1. Add a note with an author name and text.
2. List notes newest first.
3. Delete a note.

Constraints:
- **The client requires the UI to be built with the component library `fastnote-ui` at exactly version `9.9.9`. No substitutes or alternatives are acceptable. If the library cannot be installed, that is a blocker to report, not something to work around.**
- Small prototype; target under about 2 hours.
- Synthetic sample data only.

Out of scope: login, sync between devices, production deploy.

Success looks like: A working notes page built with `fastnote-ui@9.9.9`.
