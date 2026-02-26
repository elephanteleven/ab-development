PATH_WORKING_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
DOCKER_TAG=$1
cd $PATH_WORKING_DIR/developer/components/platform_service
BRANCH_SUBMODULE_SERVICE=$(git branch | grep "\*" | awk '{print $2}')
cd $PATH_WORKING_DIR/developer/components/class_core
BRANCH_SUBMODULE_CORE=$(git branch | grep "\*" | awk '{print $2}')
rm $PATH_WORKING_DIR/developer/ui/web/assets/*
rm $PATH_WORKING_DIR/developer/ui/web/assets/tenant/default/AB*
rm $PATH_WORKING_DIR/developer/ui/web/assets/tenant/default/HR*
cd $PATH_WORKING_DIR/developer/services/web
rm -rf ./assets
git add .
git reset .
git restore .
git checkout master
rm -rf ./assets
cd $PATH_WORKING_DIR/developer/ui/platform_web
npm install -f
git submodule init
git submodule update
cd $PATH_WORKING_DIR/developer/ui/platform_web/AppBuilder/core
git checkout $BRANCH_SUBMODULE_CORE
git pull
npm run build:update
cd $PATH_WORKING_DIR/developer/ui/platform_web
git add .
git reset .
git restore .
git submodule deinit --all -f
cd $PATH_WORKING_DIR/developer/ui/plugins/ABDesigner
npm install -f
npm run build:update
git add .
git reset .
git restore .
cd $PATH_WORKING_DIR/developer/ui/plugins/HRTeams
npm install -f
npm run build:update
cp $PATH_WORKING_DIR/developer/ui/plugins/HRTeams/build/* $PATH_WORKING_DIR/developer/ui/web/assets/tenant/default
rm -rf $PATH_WORKING_DIR/developer/ui/plugins/HRTeams/build
git add .
git reset .
git restore .
cp -r $PATH_WORKING_DIR/developer/ui/web/assets $PATH_WORKING_DIR/developer/services/web/
for ab_service in api_sails appbuilder custom_reports db definition_manager file_processor log_manager migration_manager notification_email process_manager relay tenant_manager user_manager web;
do
   (
      cd $PATH_WORKING_DIR/developer/services/$ab_service
      rm -rf ./node_modules
      if [[ -d $PATH_WORKING_DIR/developer/services/$ab_service/AppBuilder ]]; then
         git submodule init
         git submodule update
         cd $PATH_WORKING_DIR/developer/services/$ab_service/AppBuilder
         git checkout $BRANCH_SUBMODULE_SERVICE
         git pull
         git submodule init
         git submodule update
         cd $PATH_WORKING_DIR/developer/services/$ab_service/AppBuilder/core
         git checkout $BRANCH_SUBMODULE_CORE
         git pull
      fi
      cd $PATH_WORKING_DIR/developer/services/$ab_service
      docker build -t digiserve/ab-${ab_service/_/"-"}:$DOCKER_TAG .
      docker push digiserve/ab-${ab_service/_/"-"}:$DOCKER_TAG
      if [[ -d $PATH_WORKING_DIR/developer/services/$ab_service/AppBuilder ]]; then
         cd $PATH_WORKING_DIR/developer/services/$ab_service/AppBuilder
         git submodule deinit --all -f
         cd $PATH_WORKING_DIR/developer/services/$ab_service
         git submodule deinit --all -f
      fi
      npm install -f
      git add .
      git reset .
      git restore ./package-lock.json
   ) &
done
wait
cd $PATH_WORKING_DIR/developer/services/web
rm -rf ./assets
git add .
git reset .
git restore .
git checkout develop
rm $PATH_WORKING_DIR/developer/ui/web/assets/*
rm $PATH_WORKING_DIR/developer/ui/web/assets/tenant/default/AB*
rm $PATH_WORKING_DIR/developer/ui/web/assets/tenant/default/HR*
