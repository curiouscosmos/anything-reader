# Agent Instructions

Apply these instructions to all work in this repository.

## Code Quality
- Keep code clean, small, and easy to follow.
- Prefer simple, explicit control flow over clever abstractions.
- Avoid unnecessary complexity or duplicate logic.

## File Structure
- Keep each component in its own file when that improves clarity or reuse.
- Prefer independent, focused types and views instead of large monolithic files.
- When a feature grows, split supporting logic into dedicated files.

## Comments
- Add clear comments where the logic is non-obvious.
- Explain why something exists, not just what the code does.
- Use comments to help future developers understand important flows, edge cases, and tradeoffs.

## Error Handling
- Handle errors and exceptions wherever they can occur.
- Do not ignore failures silently unless that is explicitly acceptable.
- Prefer safe fallbacks, clear recovery paths, and user-facing error states.

## Security
- Keep code secure by default.
- Avoid force unwraps, unsafe assumptions, and accidental data exposure.
- Validate inputs, sanitize untrusted data, and prefer least-privilege behavior.
- Do not add network, file, or permission handling without a clear need and safe fallback.

## General
- Favor maintainable solutions over overly generic ones.
- Keep changes scoped to the requested task.
- Preserve existing app behavior unless a change is explicitly requested.
- For repository context, consult `AI.md` first; it contains the project map and the app flow.
