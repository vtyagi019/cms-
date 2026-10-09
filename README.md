# Techtrix 2026 Portal — Supabase Setup

This folder converts the supplied **Techtrix 2026 Portal | E-Cell** from browser-only `localStorage` storage to Supabase PostgreSQL.

## Folder contents

- `index.html` — Supabase-connected version of the portal.
- `backup/Techtrix_2026_Portal_Local_Backup.html` — original uploaded HTML kept unchanged as a backup.
- `supabase_schema.sql` — creates the database tables, indexes, seed users, seed outputs/tasks, and demo RLS policies.
- `README.md` — setup instructions.

## 1. Create the Supabase project

1. Open Supabase and create a new project.
2. Open **SQL Editor**.
3. Open `supabase_schema.sql` from this folder.
4. Paste the complete SQL into SQL Editor and click **Run**.

## 2. Get your project credentials

In Supabase open **Project Settings → API** and copy:

- Project URL
- Publishable/anon key

Never put the `service_role`/secret key into the HTML file.

## 3. Configure the HTML

Open `index.html` and find:

```js
const SUPABASE_URL = "PASTE_YOUR_SUPABASE_URL_HERE";
const SUPABASE_ANON_KEY = "PASTE_YOUR_SUPABASE_ANON_KEY_HERE";
```

Replace both values with your project's URL and publishable/anon key.

## 4. Run locally

Do not rely on opening the HTML with `file://` if the browser blocks requests. Use a tiny local web server.

### Option A — Python

From this folder:

```powershell
python -m http.server 5500
```

Then open:

`http://localhost:5500/index.html`

### Option B — VS Code Live Server

Install the Live Server extension, right-click the HTML file, and choose **Open with Live Server**.

## 5. Demo login credentials

The SQL seeds the same users that existed in the uploaded portal. Example:

- `admin1` / `Sr#4827`
- `admin2` / `An#9153`
- `creative.head` / `Vg#6204`
- `vp1.head` / `Ym#3719`
- `vp2.head` / `Dp#8452`
- `pr.head` / `Vt#5036`
- `adm.head` / `Pg#7261`
- `sr.head` / `As#1948`
- `member.demo` / `Mb#2580`

Change these before any real deployment.

## 6. What is now stored in Supabase

| Portal feature | Supabase table |
|---|---|
| Users / team | `portal_users` |
| Tasks | `portal_tasks` |
| Department output | `portal_outputs` |
| Daily feedback | `portal_posts` |

## Important security note

This first version keeps the supplied portal's custom User ID + password login so the existing UI works with minimal changes. It hashes the password before comparison, but it is **not equivalent to production-grade Supabase Auth**.

For a public deployment, the next step should be:

1. Create users with Supabase Auth.
2. Store profile/department/role in a profile table.
3. Use `auth.uid()` in RLS policies.
4. Remove the public `select` policy on `portal_users`.
5. Never expose a service-role key in frontend code.

The current SQL intentionally uses permissive demo policies so you can first confirm that the portal works end-to-end.