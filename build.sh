PATH_WORKING_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
DOCKER_TAG=$1
# The UI builds straight into developer/web/assets, the web repo's own copy, and the
# web image is built from that repo's master. It goes back to develop at the end.
cd $PATH_WORKING_DIR/developer/web
rm -rf ./assets
git add .
git reset .
git restore .
git checkout master
# No -rf, deliberately: this clears the built bundles at the top level and the plugin
# builds, while the asset subdirectories (fonts, images, ...) the image needs survive.
# rm reports "Is a directory" for each of them, which is expected.
rm ./assets/*
rm ./assets/tenant/default/AB*
rm ./assets/tenant/default/HR*
cd $PATH_WORKING_DIR/developer/ab_platform_web
npm install -f
git submodule update --init --recursive
npm run build:update
git add .
git reset .
git restore .
cd $PATH_WORKING_DIR/developer/plugins/ABDesigner
npm install -f
npm run build:update
git add .
git reset .
git restore .
cd $PATH_WORKING_DIR/developer/plugins/HRTeams
npm install -f
npm run build:update
cp $PATH_WORKING_DIR/developer/plugins/HRTeams/build/* $PATH_WORKING_DIR/developer/web/assets/tenant/default
rm -rf $PATH_WORKING_DIR/developer/plugins/HRTeams/build
git add .
git reset .
git restore .
for ab_service in web db migration_manager api_sails appbuilder custom_reports definition_manager file_processor log_manager notification_email process_manager tenant_manager user_manager;
do
   (
      cd $PATH_WORKING_DIR/developer/$ab_service
      rm -rf ./node_modules
      # Services with AppBuilder (platform_service, and its core = class_core) build
      # with the commits they record. The copies stay checked out: they are the code
      # the dev stack runs.
      if [[ -f $PATH_WORKING_DIR/developer/$ab_service/.gitmodules ]]; then
         git submodule update --init --recursive
      fi
      docker build -t digiserve/ab-${ab_service/_/"-"}:$DOCKER_TAG .
      docker push digiserve/ab-${ab_service/_/"-"}:$DOCKER_TAG
      npm install -f
      git add .
      git reset .
      git restore ./package-lock.json
   ) &
done
wait
cd $PATH_WORKING_DIR/developer/web
rm -rf ./assets
git add .
git reset .
git restore .
git checkout develop
