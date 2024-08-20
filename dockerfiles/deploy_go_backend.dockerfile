# Set go version
ARG ARG_GO_VERSION

# First stage to build
FROM golang:${ARG_GO_VERSION}-alpine as builder

WORKDIR /app

COPY . .

RUN go build -C ./src -o ../application -ldflags "-s -w"

# Second stage to run
FROM scratch

COPY --from=builder /app/application /application

ARG ARG_APP_VERSION
ENV APP_VERSION=${ARG_APP_VERSION}

CMD ["/application"]
