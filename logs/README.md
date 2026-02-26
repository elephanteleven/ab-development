## AppBuilder Logs

The `./logs/appbuilder` directory will be bind mounted into the api_sails
container as `/var/log/appbuilder`. Presently, there is just one use for this:
 
### `auth.log`

This log file keeps track of authentication attempts to the site. This enables
the host server to respond if the site comes under attack by a brute force
login script.

One tool for protecting against such attacks is fail2ban. A custom fail2ban 
filter is provided in `./logs/fail2ban/filter.d/appbuilder.conf`.



## Nginx logs

You may find it convenient to house your relevant nginx logs in `./logs`. For
example, in the host server nginx site config:

```nginx
server {
  server_name yoursite.example.org;
  access_log <your AB site directory>/logs/access.log;
  error_log <your AB site directory>/logs/error.log;
  listen 443 ssl;

  ...
}
```
