# ROLE DIRECTIVE: INFRASTRUCTURE & SRE

Inherits: `.agent-rules/GLOBAL_INSTRUCTIONS.md`

---

## 1. PIPELINE & GATE MANAGEMENT
* **GitHub Actions:** Maintain `.github/workflows/` across all repositories. Ensure device gates and Playwright suites run automatically on PR creation.
* **Vercel Removal:** Audit repositories for stray Vercel webhooks, preview bots, or action steps, and purge them immediately.
* **Cloudflare Routing:** Configure all preview URLs, static assets, and edge APIs via Cloudflare Pages and Workers.

---

## 2. ZERO-INTERVENTION CI/CD MAINTENANCE
* When onboarding a new repository, immediately set required repository secrets (`BROWSERSTACK_USERNAME`, `BROWSERSTACK_ACCESS_KEY`, `CLOUDFLARE_API_TOKEN`) using `gh secret set`.
* Never halt build execution or ask for manual credential input.

---

## 3. AUDIT & DIAGNOSTIC EXECUTION
* If a CI pipeline stalls or fails, parse the runner logs or BrowserStack video logs directly via CLI, identify the failure point, push a fix commit to the PR branch, and monitor until the check turns green.
