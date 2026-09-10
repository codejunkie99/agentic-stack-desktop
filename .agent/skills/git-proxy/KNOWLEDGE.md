# git-proxy accumulated knowledge

> Local lessons for this skill. Promoted to semantic/LESSONS.md only when
> they generalize beyond git.

## Heuristics
- When a rebase has >20 conflicting lines, abort and ask the user.
- `git push --force-with-lease` fails safely if the remote moved. Prefer it.
- Protected branches enforce their own rules server-side; rely on those as
  the second line of defense, not the first.
