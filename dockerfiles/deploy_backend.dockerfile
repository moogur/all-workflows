# Set node version
ARG ARG_NODE_VERSION

# First stage to build
FROM node:${ARG_NODE_VERSION}-alpine as builder

WORKDIR /usr/src

COPY package.json package-lock.json .npmrc ./

RUN npm ci

COPY . .

RUN npm run build

# Second stage to run
FROM node:${ARG_NODE_VERSION}-alpine

WORKDIR /usr/app

COPY --from=builder /usr/src/dist /usr/app/dist

ARG ARG_APP_VERSION
ENV APP_VERSION=${ARG_APP_VERSION}

CMD node dist/index.js
