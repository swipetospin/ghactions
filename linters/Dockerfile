FROM python:3.6-slim

LABEL "com.github.actions.name"="SpinCar PR Linter"
LABEL "com.github.actions.description"="GitHub Action to lint and annotate pull requests"
LABEL "com.github.actions.icon"="thumbs-up"
LABEL "com.github.actions.color"="green"

RUN apt-get update -y; exit 0
RUN apt-get install -y git jq curl
RUN curl -sL https://deb.nodesource.com/setup_18.x | bash -
RUN apt-get install -y nodejs

RUN npm install -g npm@9.1.1
RUN npm root -g
RUN npm install -g jshint jshint-json

RUN pip install --upgrade pip
COPY requirements.txt /requirements.txt
RUN pip install --no-cache -r /requirements.txt
RUN python --version; pip --version; flake8 --version; cfn-lint --version

COPY src /src
CMD ["/src/entrypoint.sh"]
