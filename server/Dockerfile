FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV USER=root

RUN apt update && apt install -y \
    git \
    build-essential \
    m4 \
    pkg-config \
    autoconf \
    automake \
    libtool \
    libmysqlclient-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    zlib1g-dev \
    libzip-dev \
    nlohmann-json3-dev \
    apache2 \
    php \
    php-mysql \
    php-xml \
    python3 \
    python3-pip \
    python-is-python3 \
    python3-mysqldb \
    mysql-client \
    ca-certificates \
    nano \
    curl \
    rsync \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

RUN git clone https://github.com/BOINC/boinc.git

WORKDIR /opt/boinc

RUN ./_autosetup

RUN ./configure \
    --disable-client \
    --disable-manager \
    --enable-server

RUN make -j1

RUN mkdir -p /project

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /project

CMD ["/entrypoint.sh"]