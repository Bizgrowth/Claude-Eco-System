Acceptance brief 01: simple app (expected: PASS through to preview approval)

Paste everything below the line into `/idea-intake`.

---

Business idea: A simple online appointment booking page for "Maple Street Physio", a small fictional physiotherapy clinic.

Problem: The clinic takes bookings by phone and loses about a third of calls during treatment hours, so potential patients give up.

Users:
- Patient: wants to see available time slots and book an appointment without calling.
- Clinic receptionist: wants to see the day's bookings in one list.

Must-have features:
1. Patient picks a service (initial assessment, follow-up, sports massage), then a date and an available time slot.
2. Patient enters name and email and gets an on-screen confirmation.
3. Receptionist view lists all bookings for a chosen day.
4. A slot that is booked can no longer be selected.

Constraints:
- Small prototype; target under about 2 hours.
- Synthetic sample data only. No real emails are sent and no real personal data is stored.
- No payment, no login in this version. The receptionist view can be an unlisted page.
- Designer chooses the tech stack. Keep dependencies minimal.

Out of scope: payments, SMS/email reminders, calendar sync, production deploy.

Success looks like: The client can open the preview URL, book a slot as a patient, and see that booking in the receptionist view.
