# Set go version
ARG ARG_GO_VERSION

# First stage to build
FROM golang:${ARG_GO_VERSION}-alpine as builder

WORKDIR /app

COPY . .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -C /app/src -o /application -ldflags "-s -w -extldflags '-static'"

# Second stage to run
FROM scratch

COPY --from=builder /application /application

ARG ARG_APP_VERSION
ENV APP_VERSION=${ARG_APP_VERSION}

CMD ["/application"]
