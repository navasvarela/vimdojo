# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately, not in a public issue or discussion:
[open a private report on GitHub](https://github.com/navasvarela/vimdojo/security/advisories/new).

Include what you found, how to reproduce it, and what an attacker could do with
it. Please don't include other people's data, or tokens that are still valid.

vimdojo is a personal open-source project, kept up in spare time, with no bug
bounty. I aim to acknowledge a report within a week and will keep you updated on
the fix. Once it's released, I'm happy to credit you if you'd like.

Please give me a reasonable chance to fix a problem before you disclose it.
Testing in good faith is welcome, within these limits: use only your own accounts,
don't degrade the service for others, and stop at the minimum needed to show the
problem.

## Supported versions

| What | Supported |
|---|---|
| The latest release of the plugin | Yes |
| Older releases | No: please upgrade |
| The API at `api.vimdojo.org` and the site at `vimdojo.org` | Yes: the deployed version |

## What's in scope

- **The API:** logging in as someone else, reading or changing another player's
  data, bypassing the checks on a login, or getting a token or personal data out.
- **The site:** cross-site scripting, or anything that acts on a signed-in player's
  account without their consent.
- **The verifier:** a key log that escapes its sandbox, reaches the network or
  affects another player's result.
- **The plugin:** anything that leaks the login token, or runs code from a shipped
  level beyond what that level is meant to do.
- **The repository:** a way for a pull request to reach secrets or write access
  through CI.

## What isn't a vulnerability

- **Code you run yourself.** Setup levels run the `init.lua` you edit, and custom
  packs (`challenges_dir`) can run code. That sandbox is isolation, to protect your
  real config from mistakes. It isn't a security boundary: only play packs you trust.
- **Local scores.** Progress and key logs are files on your own machine, so editing
  them is possible and only affects you.
- **A replayed key log running Vim commands.** That's how the verifier works. The
  sandbox around it is what matters: please report an escape, not the commands.
- **Public handles and the token-like analytics value in the site's source.** Both
  are public by design.
- **Advisories in dev-only dependencies** that don't reach players or the deployed
  API. They're still worth fixing, so an ordinary issue is fine for these.

## If your login token leaks

Tokens start with `vdj_` and can only act on your vimdojo account. Revoke one by
running `:VimDojo logout`, or from your [account page](https://vimdojo.org/account/).
