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
* Recommended to install <a href="http://bitop.luajit.org/">BitOp</a>.
```
cd LuaBitOp-*
make INCLUDES=-I/usr/include/lua5.1
sudo make install
```
If the above cannot find your lua include headers, try make without the INCLUDES=..., or change it based on where the dev headers are on your system.

* Copy ludebot.conf.example to ludebot.conf and edit it. Then run ./ludebot.

### Dockerfile

To use ludebot with docker:
* build the millerlogic/<a href="https://github.com/millerlogic/irccmd">irccmd</a> and millerlogic/ludebot images.
* if you want to persist the bot's state, which you probably do, link in a volume to the container's /ludebot-state
* set environment variable LUDEBOT_RUN=first if you want to have the bot generate empty state files for you if this is your first time running it. (this step may be changed/removed in the future)

Example:

```
docker run \
  --name mybot \
  -e LUDEBOT_RUN=first \
  -v "~/.ludebot-state:/ludebot-state" \
  millerlogic/ludebot
  ```
  
 Remember to remove `-e LUDEBOT_RUN=first` for the subsequent runs.
 
