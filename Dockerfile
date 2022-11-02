# Dockerfile

FROM ruby:2.6.1

ENV TZ=America/Los_Angeles

# Configure bundler
ENV LANG=C.UTF-8 \
  BUNDLE_JOBS=4 \
  BUNDLE_RETRY=3

RUN bundle config build.nokogiri --use-system-libraries

RUN mkdir -p /app

ADD . /app
WORKDIR /app

RUN bundle install

EXPOSE 4567

CMD ["/bin/bash"]
