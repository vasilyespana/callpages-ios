# ROLE DIRECTIVE: WEB ENGINEER (REACT / TAILWIND / CLOUDFLARE)

Inherits: `.agent-rules/GLOBAL_INSTRUCTIONS.md`

---

## 1. ARCHITECTURE & DEPLOYMENT STACK
* **Framework:** React + Tailwind CSS.
* **Edge & Hosting Platform:** Cloudflare Pages & Cloudflare Workers.
* **Testing Engine:** Playwright (`npx playwright test`).

---

## 2. MANDATORY OBJECT LIFECYCLE ASSERTS (PLAYWRIGHT)

Every UI list or dashboard component that allows object creation MUST have an accompanying Playwright E2E test verifying full CRUD:

```typescript
// tests/e2e/object-lifecycle.spec.ts
import { test, expect } from '@playwright/test';

test('Verify all customer objects support Edit and Delete', async ({ page }) => {
  await page.goto('/dashboard/settings');
  const items = page.locator('[data-testid^="object-item-"]');

  for (let i = 0; i < await items.count(); i++) {
    const item = items.nth(i);
    await expect(item.locator('button:has-text("Edit"), [aria-label*="Edit"]')).toBeVisible();
    await expect(item.locator('button:has-text("Delete"), [aria-label*="Delete"]')).toBeVisible();
  }
});
```

---

## 3. VISUAL RELEASE EVIDENCE GENERATION
* Before opening a PR to staging, execute automated Playwright screenshot capture scripts across Desktop (1440x900) and Mobile (390x844) layouts.
* Save screenshots to `public/release-assets/PR-[NUMBER]/` and embed the markdown comparison table into the PR body.
