# Log in

Log in lets a returning user open the app with email and password. With no users, `/user/log-in` sends the browser to first-account registration. Launch seeds a user, so the default verification instance shows the password form.

## Sub-features

- `login-form` shows Email, Password, and Keep me logged in for 14 days when users exist.
- `login-success` posts `#login_form_password` and lands on Items.
- `login-fail` keeps the user on `/user/log-in` with flash `Invalid email or password`.
- `login-closed-register` redirects `/user/register` to log in once a user exists.
- `login-required` sends `/` to `/user/log-in` when there is no session.

## How to get to it (user POV)

- Open `/user/log-in`.
- Open `/` while logged out.
- Open `/user/register` after the first account exists.

## Driving it with verify-pinventory

Preconditions:

- `verify-pinventory doctor` reports `http://127.0.0.1:4010` and user `verify@example.com`.
- Browser has no Pinventory session (fresh launch, or the login page after logout).

- **Closed registration.** Open register. Run `verify-pinventory browser goto /user/register`. The heading is `Log in` or the flash includes `Registration is closed`. `#registration_form` is absent.
- **Login required.** Open home logged out. Run `verify-pinventory browser goto /`. The URL is `/user/log-in` and `#login_form_password` is visible. `#app-nav` is absent.
- **Form.** Confirm fields. Run `verify-pinventory browser exists '#user_email'` and `verify-pinventory browser exists '#user_password'` and `verify-pinventory browser exists '#user_remember_me'`. Form text includes `Keep me logged in for 14 days`. HTML for `#user_remember_me` includes `checked=""`. Do not trust `browser attr … checked` (empty string and missing both print blank).
- **Bad password.** Fill and submit. Run `verify-pinventory browser fill '#user_email' 'verify@example.com'`, `verify-pinventory browser fill '#user_password' 'wrong-password'`, `verify-pinventory browser click '#login_form_password button'`. Wait for `#flash-error`. Text includes `Invalid email or password`. `#items-page` is absent.
- **Good password.** Run `verify-pinventory browser login`. `#items-page` is visible. Heading text is `Items`. `#nav-items` has `aria-current="page"`.
- **Proof.** Run `verify-pinventory browser screenshot log-in/items.png` and `verify-pinventory browser html log-in/items.html`. Both show `Items` and `#app-nav`.

## Gotchas

- Launch always inserts `verify@example.com`. First-account `#registration_form` is not reachable on a launched instance. Prove that path only on a database with zero users, which this harness does not create.
- Login is a LiveView that then POSTs `#login_form_password` to `/user/log-in`. Wait for `#items-page`, not for the button click to finish.
- Settings later needs sudo mode. A login from this recipe starts that window (20 minutes).
- `Keep me logged in for 14 days` is checked by default (`#user_remember_me`).
