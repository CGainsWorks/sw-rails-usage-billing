# Development / CI image. The production image is the Dockerfile at the repo root.
FROM ruby:3.3-bookworm

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
      build-essential libpq-dev libyaml-dev postgresql-client git curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /meterly

ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    RAILS_ENV=development

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 3000
CMD ["bin/rails", "server", "-b", "0.0.0.0"]
