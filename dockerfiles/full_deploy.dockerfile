# Set go version
ARG ARG_GO_VERSION
ARG ARG_NODE_VERSION

# Build backend
FROM golang:${ARG_GO_VERSION}-alpine as backend

COPY . .

RUN cd backend && make build

# Build frontend
FROM node:${ARG_NODE_VERSION}-alpine as frontend

COPY . .

RUN cd frontend && npm ci && npm run build

# Run application
FROM scratch

ARG ARG_APP_VERSION
ENV APP_VERSION=${ARG_APP_VERSION}

COPY --from=backend /backend/bin/main /main
COPY --from=frontend /frontend/dist /frontend

CMD ["/main"]
