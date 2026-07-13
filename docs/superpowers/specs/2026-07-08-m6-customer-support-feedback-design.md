# M6-3 Customer Support Feedback Design

## Scope

Build the Flutter Customer Support feedback submission slice. Users can open
Customer Support from Profile, fill email and message, select optional Type and
Function chips, submit feedback, see `Feedback submitted. Thank you.`, and
return to Profile after the form clears.

This slice is Flutter-only. It does not add the Workers `POST /feedbacks` route,
does not change the database, does not touch admin feedback management, and does
not modify `docs/tcg-card/**`.

## Existing State

Profile currently renders `Customer Support` as a static list entry. The app has
shared Toast helpers and a local placeholder repository pattern for features
that are not wired to Workers yet. The Workers schema already contains
`feedback_ticket`, but there is no front-office `/feedbacks` route in the
current codebase.

## Recommended Approach

Add a small Profile-owned feedback feature:

- Create `feedback_repository.dart` with `FeedbackSubmission`,
  `FeedbackReceipt`, `FeedbackRepository`, and `LocalFeedbackRepository`.
- Create `customer_support_page.dart` for the form and submission UI.
- Register `/customer-support` in the existing router.
- Wire Profile `Customer Support` to `context.push('/customer-support')`.
- Prefill email from `AuthSession.email` for signed-in users only.
- Keep types/functions optional and default them to `Other` inside the local
  repository when no chips are selected.

The UI validates before repository submission:

- empty email: `Please enter your email.`
- invalid email: `Please enter a valid email address.`
- empty message: `Please enter your feedback.`
- message longer than 1000 chars: disable Submit Feedback and show
  `Message must be 1000 characters or less.`

## Alternatives Considered

1. Implement Workers `POST /feedbacks` now. This would be product-correct but
   expands the slice into backend route and D1 write behavior. The current goal
   is to keep M6 app work separate from M7/Admin and schema-risk surfaces.
2. Use a Toast-only placeholder when tapping Customer Support. That would be
   simpler, but it would not satisfy the M6-3 form, validation, and submit
   behavior.
3. Put all form logic inside `profile_page.dart`. The file already handles
   account state and auth actions; a dedicated page keeps the next M6 tasks
   easier to read.

The selected approach gives the app a real UX and test seam while keeping the
backend integration replaceable.

## Behavior

The Customer Support page shows:

- title `Customer Support`
- Type chips: `Bug Report`, `Feature Request`, `Improvement`, `Other`
- Function chips: `Scan`, `Search`, `Collection`, `Portfolio`, `Wishlist`,
  `Account`, `Price Data`, `Other`
- email field with placeholder `your@email.com`
- message field with placeholder `Tell us what's on your mind...`
- `Submit Feedback`

`Subscription` is not present.

On successful submit, the page calls the repository, clears the form, shows
`Feedback submitted. Thank you.`, and returns to Profile.

On repository failure, it keeps the form content and shows
`Unable to submit feedback. Please try again later.`

## Testing

Use TDD:

- Add a widget test that opens Customer Support from Profile, verifies signed-in
  email prefill, chip options, no Subscription option, successful submit
  payload, success Toast, and return to Profile.
- Add a widget test for validation: guest email empty, invalid email, empty
  message, and >1000 char message disabling submit.
- Run the tests RED before creating the page/repository/router.
- Implement the smallest repository and page code to pass.
- Run focused widget tests and full Flutter verification.
