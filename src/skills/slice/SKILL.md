---
name: slice
description: Slicing stage. Splits an approved spec into slices, each one end-to-end observable behaviour that one session can finish, so that every acceptance criterion belongs to exactly one slice.
---

# Slice

Work only on a spec whose status is `approved`.

1. Read the spec and the components named in its `model` field.
2. For each slice copy `.softwary/templates/slice.md` to
   `specs/NNN-<name>/slices/S<n>.md`. A slice delivers one behaviour that can
   be observed end to end and finished in one session.
3. Fill in `goal`, `acs` (the criteria it delivers), `depends_on` (slices that
   must be done first) and `touches` (the paths it will change). Keep
   `status: planned`.
4. Every criterion of the spec belongs to exactly one slice. Prefer more, thin
   slices over a few wide ones.
5. Run `./softwary trace` until it passes, then `./softwary status`.

Gate: `./softwary trace` passes. Then continue with `implement`, one slice at
a time, in `depends_on` order.
