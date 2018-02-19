FROM elixir:alpine

RUN mix local.hex --force
RUN mix local.rebar --force

RUN mkdir /app
WORKDIR /app

RUN apk update
RUN apk add git curl libcurl bash

COPY . /app

ENV MIX_ENV=dev REPLACE_OS_VARS=true SHELL=/bin/sh
RUN mix deps.get

#RUN mix release
RUN mix compile

#CMD epmd -daemon && /app/run.sh #/app/_build/dev/rel/samantha/bin/samantha foreground
ENTRYPOINT ["/app/run.sh"]
#CMD /app/_build/dev/rel/samantha/bin/samantha foreground