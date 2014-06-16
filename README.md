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
