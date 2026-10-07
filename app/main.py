"""FastAPI app and AWS Lambda entry point (Mangum translates API Gateway events to ASGI, plan D-001)."""

from uuid import uuid4

from fastapi import FastAPI, Request
from fastapi.openapi.utils import get_openapi
from mangum import Mangum

from app.api.errors import ImageTooLarge, error_response, register_error_handlers
from app.api.routes import UPLOAD_PATH, router
from app.config import Settings, get_settings
from app.logging_setup import aws_request_id, configure_logging, correlation_id

CORRELATION_HEADER = "X-Correlation-Id"


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    configure_logging(settings.log_level)
    docs = settings.enable_docs  # off in the deployed function: docs are a static file (plan D-011)
    app = FastAPI(
        title="UrbanAlert Multimedia",
        version="1.0.0",
        description="Stores photographic evidence and returns its definitive URL.",
        docs_url="/docs" if docs else None,
        redoc_url=None,
        openapi_url="/openapi.json" if docs else None,
    )
    app.state.settings = settings

    # Starlette runs the last registered middleware first: correlation wraps the size check.
    @app.middleware("http")
    async def _reject_oversized_upload(request: Request, call_next):
        # Reject before parsing the multipart body; the service re-checks the real image size (RF-003).
        if request.method == "POST" and request.url.path == UPLOAD_PATH:
            declared = request.headers.get("content-length", "")
            limit = settings.max_image_bytes + settings.multipart_overhead_bytes
            if declared.isdigit() and int(declared) > limit:
                return error_response(ImageTooLarge.status_code, ImageTooLarge.message)
        return await call_next(request)

    @app.middleware("http")
    async def _correlation(request: Request, call_next):
        value = request.headers.get(CORRELATION_HEADER) or str(uuid4())
        token = correlation_id.set(value)
        context = request.scope.get("aws.context")
        request_token = aws_request_id.set(getattr(context, "aws_request_id", None))
        try:
            response = await call_next(request)
        finally:
            correlation_id.reset(token)
            aws_request_id.reset(request_token)
        response.headers[CORRELATION_HEADER] = value
        return response

    register_error_handlers(app)
    app.include_router(router)
    app.openapi = lambda: _openapi_without_422(app)
    return app


def _openapi_without_422(app: FastAPI) -> dict:
    """Validation errors are answered with 400 (plan D-008): drop FastAPI's default 422 from the contract."""
    if app.openapi_schema is None:
        schema = get_openapi(title=app.title, version=app.version, description=app.description, routes=app.routes)
        for path in schema.get("paths", {}).values():
            for operation in path.values():
                operation.get("responses", {}).pop("422", None)
        for name in ("HTTPValidationError", "ValidationError"):
            schema.get("components", {}).get("schemas", {}).pop(name, None)
        app.openapi_schema = schema
    return app.openapi_schema


app = create_app()
handler = Mangum(app, lifespan="off")
