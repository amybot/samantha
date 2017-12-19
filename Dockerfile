FROM elixir:alpine

RUN mix local.hex --force
RUN mix local.rebar --force

RUN mkdir /app
WORKDIR /app

RUN apk update
RUN apk add git

COPY . /app

RUN mix deps.get

RUN mix compile

CMD iex -S mix run
