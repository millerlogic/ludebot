ludebot
=======

ludebot - work in progress, please be patient while it comes together

Depends on
<a href="http://www.lua.org/versions.html#5.1">Lua 5.1</a>,
<a href="https://github.com/millerlogic/irccmd">irccmd</a>
and <a href="https://github.com/millerlogic/luasandy">luasandy</a>.

* Install Lua 5.1 using your platform's favorite package manager, or using the download from the Lua site. The packages may be named similarly to lua5.1 and liblua5.1-0-dev.
* Fetch and build <a href="https://github.com/millerlogic/irccmd">irccmd</a>.
* Fetch <a href="https://github.com/millerlogic/luasandy">luasandy</a>.
* Copy ludebot.conf.example to ludebot.conf and edit it. Then run ./ludebot.

### Dockerfile

To use ludebot with docker:
* Build the millerlogic/<a href="https://github.com/millerlogic/irccmd">irccmd</a> and millerlogic/ludebot images.
* Link a local path into the container's /ludebot-state. Ensure uid 28101 can write to this location. This location will hold any of the bot's persistent state and configs.
* Add your ludebot.conf to the container's ludebot-state

Example:

```
mkdir ~/.ludebot-state
cp ludebot.conf.example ~/.ludebot-state/ludebot.conf # edit as needed
chmod g+rwx ~/.ludebot-state
chgrp 28101 ~/.ludebot-state

docker run \
  --name mybot \
  -v "~/.ludebot-state:/ludebot-state" \
  millerlogic/ludebot
```
