# relaton-api (Ruby reference implementation)

Config-driven Rack application serving the Relaton API v3 contract over a
dataset directory. Sister implementation of the npm package @relaton/api;
both are pinned by the shared conformance corpus.

## Usage

    gem install relaton-api
    RELATON_DATA_DIR=./data rackup examples/config.ru

Structure and rules: autoload-only loading (no require_relative inside
lib/), routes as a registry (OCP), model-driven responses via the relaton
gem. See TODO.api/11-… in relaton/api.relaton.org for the roadmap.
