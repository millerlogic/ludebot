# Helper script run-ludebot-container.sh or run-ludebot-container-first.sh can be used,
# just pass it the path of the parent directory which contains ludebot, irccmd and luasandy.
# When run-ludebot-container-first.sh is used, directory ludebot-state will also be created.

# If not using a helper script:
# When running the container, specify the following volume from the host.
#   -v /path/to/ludebot-state:/ludebot-state # the working dir and for data files.
# On the first run only, also include -e "LUDEBOT_RUN=first"

FROM millerlogic/irccmd
USER root

# For: wordnet functionality in bot.
RUN apt-get install wordnet -y

# Pull in luasandy.
RUN mkdir -p /luasandy/lua
RUN wget --no-check-certificate -O/luasandy/lua/sandbox.lua https://raw.githubusercontent.com/millerlogic/luasandy/409ee4babf1a55417df79404d39cb0eeba4de602/lua/sandbox.lua

ENV IRCCMD_PATH /irccmd/irccmd
ENV LUDEBOT_LUA_PATH /ludebot/lua/?.lua;/irccmd/lua/?.lua;/luasandy/lua/?.lua;;

# default
ENV LUDEBOT_RUN next
ENV LUDEBOT_CONF_PATH /ludebot-state/ludebot.conf

# Add the host dir.
ADD ./ /ludebot

RUN groupadd -g 28101 container || echo
RUN useradd -u 28101 -N -g 28101 container || echo

RUN mkdir /ludebot-state
RUN chown container:container /ludebot-state

VOLUME ["/ludebot-state"]

USER container
CMD cd /ludebot-state && /ludebot/ludebot "$LUDEBOT_CONF_PATH" -- -flag=${LUDEBOT_RUN}run $IRCCMD_ARGS >>/ludebot-state/ludebot.out
