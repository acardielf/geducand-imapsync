FROM debian:bullseye

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    libauthen-ntlm-perl \
    libcgi-pm-perl \
    libcrypt-openssl-rsa-perl \
    libdata-uniqid-perl \
    libencode-imaputf7-perl \
    libfile-copy-recursive-perl \
    libfile-tail-perl \
    libio-compress-perl \
    libio-socket-ssl-perl \
    libio-socket-inet6-perl \
    libio-tee-perl \
    libhtml-parser-perl \
    libjson-webtoken-perl \
    libmail-imapclient-perl \
    libparse-recdescent-perl \
    libreadonly-perl \
    libregexp-common-perl \
    libsys-meminfo-perl \
    libterm-readkey-perl \
    libtest-mockobject-perl \
    libunicode-string-perl \
    liburi-perl \
    libwww-perl \
    libnet-server-perl \
    make \
    time \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Descarga imapsync oficial (no desde apt, sino el binario del autor)
RUN curl -s https://imapsync.lamiral.info/imapsync \
    -o /usr/local/bin/imapsync \
    && chmod +x /usr/local/bin/imapsync

COPY ./sync.sh /usr/local/bin/sync.sh

CMD ["/usr/local/bin/sync.sh"]
