# Poverty Mapping & Tracking

A community-powered issue reporting, mapping and volunteer coordination web app. Built with React, Vite, TypeScript, Tailwind CSS, Supabase Auth/Postgres/Storage/Realtime and Leaflet/OpenStreetMap.

> **Important:** This repository is an implementation scaffold that becomes data-backed after you connect your own Supabase project and apply the migration. It does not contain live credentials, users, demo reports, fake statistics, or sample map pins. A production launch still requires configuration, review of the policies against your local requirements, and end-to-end testing.

## Features included

- Public home feed and issue detail pages; no account required to browse.
- Live public issue feed and map backed by the `public_issues` view; realtime refresh when issue records change.
- Citizen/volunteer email registration and login, password reset, role stored in the database.
- Citizen report form with photo upload and browser geolocation/manual coordinates.
- Volunteer join workflow, radius preference, task list and completion evidence upload.
- Citizen-only resolution review RPC; verified fixes page only lists `RESOLVED` records.
- Supabase SQL schema, RLS policies, storage buckets, PostGIS nearby-issue RPC, and status history.
- Responsive layout inspired by the supplied CarePulse-style reference screenshots.

## 1. Requirements

- Node.js 20 or later and npm
- A Supabase project
- Git and a GitHub account
- A Vercel account for deployment

## 2. Run locally

```bash
npm install
cp .env.example .env
```

Set the following values in `.env` from **Supabase → Project Settings → API**:

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
```

Then run:

```bash
npm run dev
```

## 3. Configure Supabase

1. Open the Supabase SQL Editor.
2. Run `supabase/migrations/0001_initial_schema.sql`.
3. Confirm the `problem-evidence`, `resolution-evidence`, and `profile-avatars` Storage buckets exist.
4. In **Authentication → Providers**, enable Email. Configure email confirmation and your SMTP provider for production.
5. In **Authentication → URL Configuration**, add your local URL (for example `http://localhost:5173`) and your deployed Vercel URL to the allowed redirect URLs.
6. In **Database → Replication**, enable Realtime for `public.issues` if you want the live issue-feed refresh.
7. Keep RLS enabled. Never put the Supabase service-role key in a `VITE_` variable or frontend code.

The signup trigger creates the profile and assigns only `citizen` or `volunteer`. The database role guard prevents a user from changing their role through a normal profile update. Public issue details intentionally omit the street address and reporter contact details.

### Storage and public evidence

The migration creates public-read evidence buckets because public transparency pages need to display citizen-consented evidence. The report form requires the reporter to affirm public photo consent. For a stricter privacy model, switch buckets to private and replace public URLs with signed-URL retrieval throughout the UI. Review file size/type limits and retention requirements before launch.

## 4. GitHub

Create an empty repository on GitHub, then from this project directory:

```bash
git init
git add .
git commit -m "Initial Poverty Mapping and Tracking app"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPOSITORY.git
git push -u origin main
```

Do not commit `.env`. It is ignored by `.gitignore`.

## 5. Deploy to Vercel

1. In Vercel choose **Add New → Project** and import the GitHub repository.
2. Framework preset: **Vite**. Build command: `npm run build`. Output directory: `dist`.
3. Add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` under Project → Settings → Environment Variables.
4. Deploy, then add the Vercel URL to Supabase Auth redirect URLs.
5. Push future changes to GitHub; Vercel will build and deploy them automatically.

`vercel.json` is included to route client-side React Router paths back to `index.html`.

## 6. Main routes

- `/` public home and live transparency feed
- `/issues` public searchable issue feed
- `/issues/:id` public issue details
- `/map` public interactive issue map
- `/verified` citizen-confirmed resolutions
- `/login`, `/register`
- `/report` citizen reporting form
- `/dashboard` role-specific personal workspace
- `/volunteers` volunteer registration information

## 7. Database objects

Tables: `profiles`, `issues`, `issue_volunteers`, `issue_evidence`, `issue_comments`, `issue_supports`, `issue_status_history`, `notifications`.

View: `public_issues`.

RPC functions: `nearby_open_issues`, `join_issue`, `submit_resolution_evidence`, `citizen_review_resolution`.

## 8. Before production

- Run `npm run typecheck` and `npm run build`.
- Test signup, email confirmation, login, password reset, signout and both roles.
- Test issue reporting, upload failures, duplicate volunteer joins, leaving assignments, evidence review and disputes with separate citizen and volunteer accounts.
- Add rate limiting / abuse reporting and moderation/retention procedures appropriate to your community.
- Complete the remaining UI flows for comments/history/notifications and volunteer task progress before describing those features as fully operational.
- Have a Supabase security reviewer inspect RLS, Storage policies, RPC grants and role escalation protections. The SQL is a starter baseline, not a substitute for a security audit.

## License

Choose and add a license before publishing the repository publicly.
