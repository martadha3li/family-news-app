# Firebase Hosting + Supabase

- Create a Firebase project on the **Spark (no-cost)** plan.
- Choose **Hosting**, not **App Hosting** (requires Blaze).
- Existing website is static and connects to the independent Supabase project; do not enable Firebase database or Storage.
- In project directory run `npx firebase-tools login` and `npx firebase-tools deploy --only hosting --project YOUR_FIREBASE_PROJECT_ID`.
- Configure Supabase Auth Site URL and redirect URLs with your actual Firebase `https://YOUR_FIREBASE_PROJECT_ID.web.app` origin.
- To automate deploys securely, run `npx firebase-tools init hosting:github` and authorize the GitHub repository. Store deployment credentials only in GitHub Actions secrets; never commit service account JSON.
- Hosting deploy and live account sign-in still need verification. Do not invite family members until access controls and privacy have been tested.
