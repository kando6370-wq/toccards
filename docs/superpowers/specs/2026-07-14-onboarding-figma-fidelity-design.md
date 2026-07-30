# Startup Onboarding Figma Fidelity Design

## Goal

Rebuild the complete first-launch flow in Flutter from the Figma design and
the checked-in source artwork. The reference viewport is 390 x 844. Other
phone widths from 320 to 430 pixels must remain usable without overflow or
overlap; a separate desktop layout is out of scope.

## Scope

The first-launch flow contains five visual states:

1. Splash screen.
2. Guide page 1.
3. Guide page 2.
4. Guide page 3.
5. Login/register entry.

Existing anonymous-session creation, authentication, onboarding completion,
and route behavior remain authoritative. Backend contracts and database
schemas are not changed.

## Design Sources

- Figma file `DjacfTioobtRy59SnqH7SY`.
- Auth/onboarding section `183:8753` and its individual child frames.
- Checked-in source artwork under
  `docs/tcg-card/source-tcg-card-docs/ui/启动引导/`.
- Existing design tokens in `KandoColors`.

Figma child frames must be read individually before implementation. Section
metadata is only an index and is not sufficient as a visual specification.

## Interaction Flow

The splash screen remains visible for at least 1.2 seconds and also waits for
the existing authentication initialization to settle. It then advances to the
first guide page.

Guide pages use horizontal paging. `Next` advances one page. `Skip` bypasses
the remaining guide content and opens the login/register entry; it does not
complete onboarding by itself.

The final entry primary action opens the existing `showAuthSheet()` flow. A
successful user login completes onboarding and reveals Home. Dismissing or
failing authentication leaves the user on the entry page. `Skip and start
now` completes onboarding as the current anonymous user and reveals Home.

## UI Architecture

Keep `OnboardingGate`, `OnboardingController`, and `OnboardingRepository` as
the module boundary. `OnboardingPage` owns only transient presentation state:
splash visibility and the current guide index.

Build text, controls, pagination, safe-area spacing, and responsive layout as
native Flutter widgets. Export or reuse only background, logo, and illustration
assets. Do not render a complete screen image or place transparent hit targets
over baked-in controls.

The existing remote-image path remains supported for configured guide images.
Default guide content uses bundled assets so the first-launch flow is complete
offline. Asset failures must show an explicit, stable fallback instead of
silently collapsing layout.

## Visual Rules

- Match Figma at 390 x 844 for geometry, spacing, typography, colors, borders,
  radii, and control states.
- Preserve stable layout dimensions while images load or fail.
- Use existing color tokens unless a missing Figma semantic token is required.
- Respect safe areas without duplicating Figma's mocked operating-system chrome.
- Keep labels and controls readable at 320 pixels wide without clipping.

## Failure Handling

- Empty slide configuration fails visibly with a stable fallback screen.
- Remote image failure uses the bundled fallback artwork and retains geometry.
- Authentication errors remain owned and displayed by the existing Auth flow.
- Splash initialization must not create a second auth initialization path.

## Verification

Widget tests must express the business intent of the first-launch flow:

- users cannot reach Home before onboarding is completed;
- splash waits for its minimum duration;
- guide navigation and skip both reach the entry page;
- dismissing Auth does not complete onboarding;
- authenticated completion and anonymous skip both persist completion;
- the next app build with the same storage bypasses onboarding;
- 390 x 844 and 320 x 700 layouts render without Flutter exceptions.

Run focused onboarding tests first, then the complete Flutter test suite and
`flutter analyze`. Finally compare browser screenshots at 390 x 844 against
the corresponding Figma frames for all five states.

## Non-Goals

- Redesigning Auth screens beyond the existing sheet entry point.
- Changing app-config, Workers API, D1, or admin behavior.
- Adding a desktop-specific onboarding composition.
- Refactoring unrelated shared UI or navigation code.
