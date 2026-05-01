FROM ubuntu AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && apt install -y \
    git \
    build-essential \
    m4 \
    pkg-config \
    autoconf \
    automake \
    libtool \
    libssl-dev \
    libcurl4-openssl-dev \
    zlib1g-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

RUN git clone https://github.com/BOINC/boinc.git

WORKDIR /opt/boinc

RUN ./_autosetup

RUN ./configure \
    --disable-server \
    --enable-client \
    --disable-manager

RUN make -j"$(nproc)"


FROM ubuntu AS runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && apt install -y \
    libcurl4 \
    libssl3 \
    zlib1g \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /boinc

COPY --from=builder /opt/boinc/client/boinc /usr/local/bin/boinc
COPY --from=builder /opt/boinc/client/boinccmd /usr/local/bin/boinccmd

CMD ["boinc", "--help"]