FROM ubuntu

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
    freeglut3-dev \
    libxmu-dev \
    libxi-dev \
    libjpeg-dev \
    libxss-dev \
    libwxgtk3.2-dev \
    libwxgtk-webview3.2-dev \
    libnotify-dev \
    libxcb-util-dev \
    libx11-dev \
    libgtk-3-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

RUN git clone https://github.com/BOINC/boinc.git

WORKDIR /opt/boinc

RUN ./_autosetup

RUN ./configure --disable-server --enable-client --disable-manager

RUN make -j"$(nproc)"

CMD ["bash"]