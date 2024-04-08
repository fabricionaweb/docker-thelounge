# syntax=docker/dockerfile:1-labs
FROM public.ecr.aws/docker/library/alpine:3.19 AS base
ENV TZ=UTC
WORKDIR /src

# source stage =================================================================
FROM base AS source

# get and extract source from git
ARG BRANCH
ARG VERSION
ADD https://github.com/thelounge/thelounge.git#${BRANCH:-v$VERSION} ./

# set home
RUN echo "/config" > .thelounge_home

# build stage ==================================================================
FROM base AS build-app

# dependencies
RUN apk add --no-cache nodejs-current && corepack enable

# node_modules
COPY --from=source /src/package*.json /src/yarn.lock /src/tsconfig*.json ./
RUN yarn install --frozen-lockfile --network-timeout 120000

# build app
COPY --from=source /src/babel.config.cjs /src/postcss.config.js /src/webpack.config.ts ./
COPY --from=source /src/client ./client
COPY --from=source /src/server ./server
COPY --from=source /src/shared ./shared
COPY --from=source /src/defaults ./defaults
RUN NODE_ENV=production yarn build

# cleanup
RUN yarn install --production --ignore-scripts --prefer-offline && \
    find ./ -type f \( \
        -iname "*.ts" -o -name "*.map" -o -iname "*.md" -o -iname "*.sh" -o \
        -iname "babel.config*" -o -iname "webpack.config*" -o -iname "tsconfig*" \
    \) -delete && \
    find ./node_modules -type f \( \
        -iname "Makefile*" -o -iname "README*" -o -iname "LICENSE*" -o -iname "CHANGELOG*" \
    \) -delete && \
    find ./node_modules -type d \( \
        -iname "test" -o -iname "node-gyp" -o -iname ".github" \
    \) -prune | xargs rm -rf && \
    ln -sf ../package.json ./dist/package.json

# runtime stage ================================================================
FROM base

ENV S6_VERBOSITY=0 S6_BEHAVIOUR_IF_STAGE2_FAILS=2 PUID=65534 PGID=65534
WORKDIR /config
VOLUME /config
EXPOSE 9000

# copy files
COPY --from=source /src/package.json /src/index.js /src/.thelounge_home /app/
COPY --from=source /src/client/index.html.tpl /app/client/
COPY --from=build-app /src/node_modules /app/node_modules
COPY --from=build-app /src/dist /app/dist
COPY --from=build-app /src/public /app/public
COPY ./rootfs/. /

# runtime dependencies
RUN apk add --no-cache tzdata s6-overlay nodejs-current curl

# run using s6-overlay
ENTRYPOINT ["/entrypoint.sh"]
