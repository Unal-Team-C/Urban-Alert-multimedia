# Same image runs locally (the base image ships the Lambda Runtime Interface Emulator)
# and in AWS Lambda as a container image (plan D-003).
FROM public.ecr.aws/lambda/python:3.13 AS runtime
COPY requirements.txt ${LAMBDA_TASK_ROOT}/
RUN pip install --no-cache-dir -r ${LAMBDA_TASK_ROOT}/requirements.txt --target ${LAMBDA_TASK_ROOT}
COPY app ${LAMBDA_TASK_ROOT}/app
CMD ["app.main.handler"]

# Test image: runtime + dev dependencies + tests. Runs pytest instead of the RIE.
FROM runtime AS test
COPY requirements-dev.txt pyproject.toml ${LAMBDA_TASK_ROOT}/
RUN pip install --no-cache-dir -r ${LAMBDA_TASK_ROOT}/requirements-dev.txt
COPY tests ${LAMBDA_TASK_ROOT}/tests
COPY docs ${LAMBDA_TASK_ROOT}/docs
ENTRYPOINT []
CMD ["pytest"]
