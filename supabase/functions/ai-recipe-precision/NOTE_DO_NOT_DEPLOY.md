# Do not deploy from this directory yet

`index.ts` and `deno.json` in this directory were pulled from the **live**
Supabase project via:

```
supabase functions download ai-recipe-precision --project-ref xwugnhzlnfgmczkbbcbh --use-api
```

on 2026-08-15 (see CLAUDE.md Roadmap item 16). This is a downloaded artifact
of what's currently deployed — it has not been hand-reviewed, edited, or
re-tested against the live project since download.

**Do not run `supabase functions deploy ai-recipe-precision` from this
directory** until Harris has confirmed the source is clean and reviewed —
even though it reads as normal, readable, hand-authored TypeScript (not a
bundled/minified blob), "looks fine on read" is not the same as "confirmed."
A `deploy` from here would overwrite the live function with this file
verbatim — low risk given it's a straight pull of the current live version,
but skip it until that confirmation happens anyway, per the same
"confirm before pushing to prod" convention this project already uses for
migrations and other edge functions (see "What this is" section, top of
CLAUDE.md).

Remove this note once Harris has reviewed `index.ts` and lifted the hold.
