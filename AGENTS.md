# Project collaboration rules

- Before a major architectural change, audio data-path refactor, interface change,
  or broad RTL rewrite, commit the current working state and push it to `origin`.
- Small fixes may be grouped into the next meaningful checkpoint.
- Do not commit Gowin implementation output, simulator work libraries, waveform
  files, user-local IDE state, or temporary analysis files.
- Do not run Gowin synthesis or place-and-route solely for automated verification;
  use RTL syntax/elaboration checks unless the project owner explicitly requests it.

