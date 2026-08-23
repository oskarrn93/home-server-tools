FROM golang:1.27-alpine3.24 AS build

WORKDIR /src
COPY go.mod main.go ./
RUN CGO_ENABLED=0 go build -o /healthcheck .

FROM alpine:3.24
COPY --from=build /healthcheck /healthcheck
EXPOSE 8080
ENTRYPOINT ["/healthcheck"]
