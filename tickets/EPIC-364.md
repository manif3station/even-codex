# EPIC-364

## Title

Reuse DD web routes for the Even plugin connector.

## Goal

Move the phone-side Even plugin connector onto the Developer Dashboard web
stack by reusing skill-local `config/routes.json`, `dashboards/ajax`, and
`dashboards/public` surfaces instead of relying only on the standalone bridge
routes, while making the documented and proven operator flow use the native DD
smart routes and helper-user session auth.

## Tickets

- `DD-364` Add the DD-served Even plugin connector surface.

## Status

done
