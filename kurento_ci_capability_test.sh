#!/bin/bash

# Test autostart KMS

if [ $# -lt 2 ]
then
  echo "Usage: $0 <groups> <test> [<record_tests>]"
  exit 1
fi

TEST_GROUP=$1
TEST_PREFIX=$2

if [ -n "$3" ]; then
  TEST_SELENIUM_RECORD=$3
else
  TEST_SELENIUM_RECORD="false"
fi

# Set constants and environment
PUBLIC_IP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
echo "Found public IP: $PUBLIC_IP"

# Create test files container
TEST_FILES_NAME="$BUILD_TAG-TEST-FILES"
docker run \
  --rm \
	--name $TEST_FILES_NAME \
    -v /var/lib/jenkins/test-files:/var/lib/jenkins/test-files \
    -w /var/lib/jenkins/test-files \
     kurento/svn-client:1.0.0 svn checkout http://files.kurento.org/svn/kurento

# Create temporary folder for container
TEST_WORKSPACE=$WORKSPACE/tmp
mkdir $TEST_WORKSPACE

# Craete Integration container
TEST_HOME=/opt/kurento-java

MAVEN_OPTS=""
MAVEN_OPTS="$MAVEN_OPTS -Dtest.kms.docker.image.forcepulling=false"
MAVEN_OPTS="$MAVEN_OPTS -Djava.awt.headless=true"
MAVEN_OPTS="$MAVEN_OPTS -Dwdm.chromeDriverUrl=http://chromedriver.kurento.org/"
MAVEN_OPTS="$MAVEN_OPTS -Dtest.kms.autostart=test"
MAVEN_OPTS="$MAVEN_OPTS -Dtest.kms.scope=docker"
MAVEN_OPTS="$MAVEN_OPTS -Dproject.path=$TEST_HOME/kurento-integration-tests/kurento-test"
MAVEN_OPTS="$MAVEN_OPTS -Dtest.workspace=$TEST_HOME/tmp"
MAVEN_OPTS="$MAVEN_OPTS -Dtest.workspace.host=$TEST_WORKSPACE"
MAVEN_OPTS="$MAVEN_OPTS -Dtest.files=/var/lib/test-files/kurento"
MAVEN_OPTS="$MAVEN_OPTS -Dtest.kms.docker.image.name=kurento/kurento-media-server-dev:latest"
MAVEN_OPTS="$MAVEN_OPTS -Dtest.selenium.scope=docker"
MAVEN_OPTS="$MAVEN_OPTS -Dtest.selenium.record=$TEST_SELENIUM_RECORD"
MAVEN_OPTS="$MAVEN_OPTS -Dgroups=$TEST_GROUP"
MAVEN_OPTS="$MAVEN_OPTS -Dtest=$TEST_PREFIX*"

# Execute Presenter test
docker run --rm \
  --name $BUILD_TAG-INTEGRATION \
  -v /var/lib/jenkins/test-files:/var/lib/test-files \
  -v $MAVEN_SETTINGS:/opt/kurento-settings.xml \
  -v $KURENTO_SCRIPTS_HOME:/opt/adm-scripts \
  -v $WORKSPACE:$TEST_HOME \
  -v $TEST_WORKSPACE:$TEST_HOME/tmp \
  -e "WORKSPACE=$TEST_HOME" \
  -e "MAVEN_SETTINGS=/opt/kurento-settings.xml" \
  -e "MAVEN_OPTS=$MAVEN_OPTS" \
  -w $TEST_HOME \
  -u "root" \
  kurento/dev-integration:jdk-8-node-0.12 \
  /opt/adm-scripts/kurento_capability_test.sh kurento-integration-tests/kurento-test || status=$?

exit $status