Acceptance brief 02: data dashboard (expected: PASS through to preview approval; heavier run)

Paste everything below the line into `/idea-intake`.

---

Business idea: A weekly sales dashboard for "Harbor Coffee Roasters", a small fictional online coffee roaster.

Problem: The owner combines order exports in a spreadsheet every Monday and still cannot tell which products and customer segments are growing.

Users:
- Owner: wants a quick weekly picture of revenue, orders and best-selling products.
- Operations manager: wants to spot slow-moving products before reordering beans.

Must-have features:
1. Load a CSV of orders (the agent generates a synthetic sample file with about 500 rows covering 12 weeks: date, product, quantity, unit price, customer segment).
2. Summary tiles: total revenue, order count, average order value for the selected week, each with change versus the previous week.
3. A revenue-over-time chart and a top-products table, both filterable by customer segment.
4. A clear empty state and an error message if an uploaded CSV has the wrong columns.

Constraints:
- Small prototype; target under about 2 hours.
- Synthetic data only. No real customer data.
- No login and no database; data stays in the browser or in a local file in this version.
- Designer chooses the tech stack. Keep dependencies minimal.

Out of scope: live connections to Shopify or any other store, forecasting, user accounts, production deploy.

Success looks like: The client opens the preview, sees the sample data populate the tiles and chart, switches segment and week, and sees a friendly error when they upload a bad file.
