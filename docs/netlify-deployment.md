# Netlify deployment

The canonical production origin is `https://dmxtract.sho.run`.

1. Import the Git repository into Netlify. The repository-root
   `netlify.toml` supplies the build command, publish directory, security
   headers, SPA fallback, and same-origin fixture-lookup function route.
2. Add `dmxtract.sho.run` as the site's custom domain in Netlify.
3. At the DNS provider for `sho.run`, create the `dmxtract` CNAME using the
   Netlify target shown for that site. Do not guess or commit the generated
   Netlify hostname.
4. Wait for Netlify to issue HTTPS before testing the local bridge. Pairing
   tokens are bound to the exact browser origin, so a deploy-preview origin
   and `dmxtract.sho.run` are paired separately.
5. Leave fixture lookup disabled for the first smoke test, or add
   `DMXTRACT_FIXTURE_LOOKUP_URL` and the optional token through Netlify's
   encrypted environment settings.

If a standalone DMXtract domain is added later, make it a permanent redirect
to `https://dmxtract.sho.run`; keep the subdomain as the canonical URL unless
the fixture schema identifier is deliberately versioned and migrated.
