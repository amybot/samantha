FROM elixir:alpine

RUN mix local.hex --force
RUN mix local.rebar --force

RUN mkdir /app
WORKDIR /app

RUN apk update
RUN apk add git make curl libcurl gawk

COPY . /app

RUN mix deps.get

RUN mix compile

CMD epmd -daemon && mix run --no-halt
