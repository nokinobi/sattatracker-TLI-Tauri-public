# TLI Sattatracker (fork)

Tauri 2 + Vue 3 tracker for Torchlight Infinite. It reads the game's log and shows profit in an in-game overlay and an F6 dashboard.

## Rules

- **Commits:** Conventional Commits only: `type(scope): description`.
- **Pull requests:** never to the original project (sattatrapy) unless asked; pull requests within this fork are fine. Release flow: `docs/release/RELEASING.md`.
- **Review comments:** every comment is fixed in the same pull request. No follow-up pull requests for review findings.
- **Privacy:** never collect, log or show other players' names or IDs. Strip them from strategy server answers.
- **Strategy server:** don't name it in new code (variables, classes, UI text); call it the strategy server. Cache answers and don't send bursts of requests.
- **Wind endpoints:** `windboard` and `wind-detail` are not used; they are unreliable.
- **Overlay input:** the Compact Window and other click-through widgets never get keyboard focus, so use sliders, checkboxes and buttons there, not text fields. Text fields are fine in the F6 dashboard.
- **Saved data:** settings and state from older versions must still load; validate everything read from `localStorage` or disk.
- **Rust:** no `unwrap`/`expect` on data from files, the network or the game log. Tauri commands validate their arguments. Logic changes keep or extend the `#[cfg(test)]` tests next to them.
- **Docs:** user-visible changes update `docs/features/`. Images there are rendered from the design, not screenshots, unless the page says otherwise.
