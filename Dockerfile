# Dockerfile

FROM ruby:3.0.4

ENV TZ=America/Los_Angeles

# Configure bundler
ENV LANG=C.UTF-8 \
  BUNDLE_JOBS=4 \
  BUNDLE_RETRY=3

RUN gem update --system
RUN bundle config build.nokogiri --use-system-libraries
RUN bundle config --global frozen 1

RUN mkdir -p /app

ADD . /app
WORKDIR /app

RUN bundle install

EXPOSE 4567

CMD ["bundle", "exec", "rackup", "config.ru", "-p", "4567", "--host", "0.0.0.0"]
