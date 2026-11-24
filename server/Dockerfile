FROM alpine:3.22 AS zig
ARG TARGETARCH
RUN apk add --no-cache curl xz
RUN case "${TARGETARCH}" in \
      amd64) echo "x86_64 3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a" ;; \
      arm64) echo "aarch64 a1546d5646eb184437918d6635ca6b762a0e889eac09cef720ee7a1ed3fe7795" ;; \
      *) echo "unsupported: ${TARGETARCH}" && exit 1 ;; \
    esac > /zig.txt
RUN read arch sum < /zig.txt \
 && curl -fsSL -o /zig.tar.xz "https://ziglang.org/download/0.17.1/zig-${arch}-linux-0.17.1.tar.xz" \
 && echo "${sum}  /zig.tar.xz" | sha256sum -c - \
 && mkdir /zig && tar -xJf /zig.tar.xz -C /zig --strip-components=1 && rm /zig.tar.xz
ENV PATH=/zig:$PATH
WORKDIR /app
COPY build.zig build.zig.zon ./
COPY zig-pkg zig-pkg

FROM zig AS server
COPY src/serve src/serve
RUN --mount=type=cache,target=/root/.cache/zig \
    read arch sum < /zig.txt \
 && zig build server -Doptimize=ReleaseSafe -Dtarget=${arch}-linux-musl --prefix /out

FROM zig AS site
COPY src/gen src/gen
RUN --mount=type=cache,target=/root/.cache/zig zig build gen
COPY content content
RUN --mount=type=cache,target=/root/.cache/zig zig build site --prefix /out

FROM zig AS development
RUN apk add --no-cache watchexec
COPY src src
COPY content content
RUN zig build
CMD ["watchexec", "--poll", "-r", "-w", "src", "-w", "content", "-w", "build.zig", "--", "zig", "build", "serve"]

FROM scratch AS production
COPY --from=server /out/bin/serve /serve
COPY --from=site /out/public /public
USER 65534:65534
EXPOSE 3000
ENTRYPOINT ["/serve", "/public"]
