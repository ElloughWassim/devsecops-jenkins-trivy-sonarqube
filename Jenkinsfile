// DevSecOps pipeline for the React/TMDB movie app:
// quality (SonarQube) -> dependencies (OWASP Dependency-Check) -> Trivy fs -> image build -> Trivy image
// -> push -> deploy (container or Kubernetes) -> e-mail report.
//
// Uses https://github.com/ElloughWassim/jenkins-pipeline-library registered in Jenkins as
// "jenkins-pipeline-library". See README.md > "Jenkins setup" for plugins, tools and credentials.
@Library('jenkins-pipeline-library@v1.0.0') _

def image

pipeline {
    agent any

    tools {
        nodejs 'node22'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 60, unit: 'MINUTES')
    }

    parameters {
        choice(name: 'REGISTRY', choices: ['dockerhub', 'ecr'], description: 'Container registry for the image')
        choice(name: 'DEPLOY_TARGET', choices: ['kubernetes', 'container', 'none'],
               description: 'kubernetes: apply k8s/ to the cluster; container: run on the Jenkins agent (port 8081)')
    }

    environment {
        // ---- Replace the placeholders (or define them as global Jenkins environment variables) ----
        DOCKERHUB_NAMESPACE = '<DOCKERHUB_NAMESPACE>'
        AWS_ACCOUNT_ID      = '<AWS_ACCOUNT_ID>'
        AWS_REGION          = 'eu-west-1'
        IMAGE_NAME          = 'movie-app'
        // Leave empty to disable the e-mail notification.
        NOTIFY_EMAIL        = ''
    }

    stages {
        stage('Install dependencies') {
            steps { sh 'yarn install --frozen-lockfile --non-interactive' }
        }

        stage('Type check and build') {
            steps { sh 'yarn build' }
        }

        stage('SonarQube analysis') {
            steps {
                sonarQubeAnalysis(installationName: 'sonarqube', scanner: 'cli', scannerTool: 'sonar-scanner')
            }
        }

        stage('Quality gate') {
            steps { sonarQubeQualityGate(timeoutMinutes: 10) }
        }

        stage('OWASP Dependency-Check') {
            steps {
                // The project uses yarn.lock (no package-lock.json), so the npm audit analyzer is disabled.
                owaspDependencyCheck(odcInstallation: 'dependency-check', nvdApiKeyCredentialsId: 'nvd-api-key',
                                     failOnCvss: 7, extraArguments: '--disableNodeAudit')
            }
        }

        stage('Trivy filesystem scan') {
            steps { trivyScan(type: 'fs', target: '.') }
        }

        stage('Docker build') {
            steps {
                script {
                    Map imageConfig = params.REGISTRY == 'ecr'
                        ? [registry: 'ecr', awsAccountId: env.AWS_ACCOUNT_ID, awsRegion: env.AWS_REGION,
                           name: env.IMAGE_NAME, tags: imageTags(extraTags: [])]
                        : [registry: 'dockerhub', namespace: env.DOCKERHUB_NAMESPACE,
                           name: env.IMAGE_NAME, tags: imageTags(extraTags: ['latest'])]
                    // The key is read by Docker from the environment (null value), never put on the command line.
                    withCredentials([string(credentialsId: 'tmdb-api-key', variable: 'TMDB_V3_API_KEY')]) {
                        image = dockerBuild(image: imageConfig, buildArgs: [TMDB_V3_API_KEY: null])
                    }
                }
            }
        }

        stage('Trivy image scan') {
            steps { trivyScan(type: 'image', target: image.primaryReference) }
        }

        stage('Push image') {
            steps {
                script {
                    if (params.REGISTRY == 'ecr') {
                        dockerPush(image: image, awsCredentialsId: 'aws-credentials')
                    } else {
                        dockerPush(image: image, credentialsId: 'dockerhub-credentials')
                    }
                }
            }
        }

        stage('Deploy to container') {
            when { expression { params.DEPLOY_TARGET == 'container' } }
            steps {
                // Replaces the previous container, so the stage can run on every build.
                sh 'docker rm -f movie-app || true'
                sh "docker run -d --name movie-app --restart unless-stopped -p 8081:8080 '${image.primaryReference}'"
            }
        }

        stage('Deploy to Kubernetes') {
            when { expression { params.DEPLOY_TARGET == 'kubernetes' } }
            steps {
                kubernetesDeploy(manifests: 'k8s', namespace: 'movie-app', deployment: 'movie-app',
                                 image: image.primaryReference, kubeconfigCredentialsId: 'kubeconfig')
            }
        }
    }

    post {
        always {
            script {
                if (image && params.DEPLOY_TARGET != 'container') {
                    dockerCleanup(image: image)
                }
                if (env.NOTIFY_EMAIL?.trim()) {
                    emailext(
                        to: env.NOTIFY_EMAIL,
                        subject: "${env.JOB_NAME} #${env.BUILD_NUMBER}: ${currentBuild.currentResult}",
                        body: "Project: ${env.JOB_NAME}<br/>Build: ${env.BUILD_NUMBER}<br/>" +
                              "Result: ${currentBuild.currentResult}<br/>URL: ${env.BUILD_URL}",
                        mimeType: 'text/html',
                        attachLog: true,
                        attachmentsPattern: 'reports/trivy/*.txt'
                    )
                }
            }
        }
    }
}
