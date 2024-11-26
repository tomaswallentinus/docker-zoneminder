# Base Image
FROM debian:latest

# Environment Variables
ENV ZM_DB_HOST=mariadb
ENV ZM_DB_NAME=zm
ENV ZM_DB_USER=zmuser
ENV ZM_DB_PASS=zmpass
ENV TZ=Europe/Stockholm

# Set ARG for non-interactive installations
ARG DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN set -x && apt-get update && \
    apt-get install --yes \
        apache2 \
        arp-scan \
        build-essential \
        cpanminus \
        ffmpeg \
        gifsicle \
        git \
        gnupg2 \
        libapache2-mod-php \
        libarchive-zip-perl \
        libclass-std-fast-perl \
        libconfig-inifiles-perl \
        libcrypt-mysql-perl \
        libcrypt-eksblowfish-perl \
        libcurl4-gnutls-dev \
        libdata-entropy-perl \
        libdata-uuid-perl \
        libdatetime-perl \
        libdate-manip-perl \
        libdbd-mysql-perl \
        libdevice-serialport-perl \
        libgeos-dev \
        libgsoap-2.8.124 \
        libimage-info-perl \
        libio-interface-perl \
        libio-socket-multicast-perl \
        libjson-maybexs-perl \
        libjson-perl \
        libjwt-dev \
        liblwp-protocol-https-perl \
        libmime-lite-perl \
        libmime-tools-perl \
        libmodule-build-perl \
        libmosquittopp1 \
        libnet-sftp-foreign-perl \
        libnumber-bytes-human-perl \
        libphp-serialization-perl \
        libsoap-wsdl-perl \
        libsys-cpu-perl \
        libsys-meminfo-perl \
        libsys-mmap-perl \
        liburi-encode-perl \
        libyaml-perl \
        libvncclient1 \
        lsb-release \
        mariadb-client \
        php \
        php-apcu \
        php-curl \
        php-gd \
        php-intl \
        php-mysql \
        php-xml \
        policykit-1 \
        python3-opencv \
        python3-pip \
        python3-requests \
        rsyslog \
        s6 \
        sudo \
        tzdata \
        wget \
        zip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Add ZoneMinder's GPG key
RUN wget -O - https://zmrepo.zoneminder.com/debian/archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/zoneminder-archive-keyring.gpg

# Fetch the latest ZoneMinder package for amd64 from the Packages file
RUN CODENAME=$(lsb_release -cs) && \
    if [ "$CODENAME" != "bookworm" ] && [ "$CODENAME" != "bullseye" ]; then \
        CODENAME="bullseye"; \
    fi && \
    BASE_URL="https://zmrepo.zoneminder.com/debian/master/$CODENAME" && \
    echo "Using ZoneMinder repository: $BASE_URL" && \
    wget -q $BASE_URL/Packages.xz -O Packages.xz && \
    unxz Packages.xz && \
    LATEST_ZONEMINDER=$(awk '/Package: zoneminder$/,/^$/' Packages | \
        awk '/Architecture: amd64/,/^$/' | \
        grep "Filename:" | tail -n 1 | awk '{print $2}') && \
    echo "Latest ZoneMinder package: $LATEST_ZONEMINDER" && \
    wget https://zmrepo.zoneminder.com/debian/master/$LATEST_ZONEMINDER -O zoneminder.deb && \
    dpkg -i zoneminder.deb || apt-get -f install --yes && \
    rm Packages zoneminder.deb

# Install Perl WebSocket module
RUN /usr/bin/cpanm -i 'Net::WebSocket::Server'

# Copy additional configurations
COPY ./content/ /tmp/

RUN install -m 0644 -o root -g root /tmp/zm-site.conf /etc/apache2/sites-available/zm-site.conf \
    && install -m 0644 -o www-data -g www-data /tmp/zmcustom.conf /etc/zm/conf.d/zmcustom.conf \
    && install -m 0755 -o root -g root -d /etc/services.d /etc/services.d/zoneminder /etc/services.d/apache2 \
    && install -m 0755 -o root -g root /tmp/zoneminder-run /etc/services.d/zoneminder/run \
    && install -m 0755 -o root -g root /tmp/zoneminder-finish /etc/services.d/zoneminder/finish \
    && install -m 0755 -o root -g root /tmp/apache2-run /etc/services.d/apache2/run \
    && install -m 0644 -o root -g root /tmp/status.conf /etc/apache2/mods-available/status.conf \
    && a2dissite 000-default \
    && a2ensite zm-site \
    && bash -c 'install -m 0755 -o www-data -g www-data -d /var/lib/zmeventnotification /var/lib/zmeventnotification/{bin,contrib,images,mlapi,known_faces,unknown_faces,misc,push}' \
    && install -m 0755 -o www-data -g www-data /tmp/zmeventnotification/zmeventnotification.pl /usr/bin/zmeventnotification.pl \
    && install -m 0755 -o www-data -g www-data /tmp/zmeventnotification/pushapi_plugins/pushapi_pushover.py /var/lib/zmeventnotification/bin/pushapi_pushover.py \
    && install -m 0755 -o www-data -g www-data /tmp/zmeventnotification/hook/zm_event_start.sh /var/lib/zmeventnotification/bin/zm_event_start.sh \
    && install -m 0755 -o www-data -g www-data /tmp/zmeventnotification/hook/zm_event_end.sh /var/lib/zmeventnotification/bin/zm_event_end.sh \
    && install -m 0755 -o www-data -g www-data /tmp/zmeventnotification/hook/zm_detect.py /var/lib/zmeventnotification/bin/zm_detect.py \
    && install -m 0755 -o www-data -g www-data /tmp/zmeventnotification/hook/zm_train_faces.py /var/lib/zmeventnotification/bin/zm_train_faces.py \
    && pip install --break-system-packages newrelic \
    && cd /tmp/zmeventnotification/hook && pip -v install --break-system-packages . \
    && rm -Rf /tmp/*

# Define Volumes
VOLUME /var/cache/zoneminder
VOLUME /var/log/zm

# Copy entrypoint script
COPY entrypoint.sh /opt/
RUN chmod +x /opt/entrypoint.sh

# Set entrypoint
ENTRYPOINT [ "/bin/bash", "-c", "source ~/.bashrc && /opt/entrypoint.sh ${@}", "--" ]

# Expose Ports
EXPOSE 80
EXPOSE 9000
