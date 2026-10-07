"""Service exceptions and handlers that normalize every error to {code, message[, details]} (plan D-008)."""

import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.api.schemas import ErrorDetail, ErrorResponse

logger = logging.getLogger(__name__)


class ServiceError(Exception):
    status_code = 500
    message = "Internal server error"

    def __init__(self, details: list[ErrorDetail] | None = None):
        super().__init__(self.message)
        self.details = details


class InvalidParameter(ServiceError):
    status_code = 400
    message = "Invalid parameter"


class ImageNotFound(ServiceError):
    status_code = 404
    message = "Image not found"


class ImageTooLarge(ServiceError):
    status_code = 413
    message = "Image exceeds the maximum size"


class UnsupportedImageFormat(ServiceError):
    status_code = 415
    message = "Unsupported image format"


class StorageUnavailable(ServiceError):
    status_code = 503
    message = "Service unavailable"


def error_response(code: int, message: str, details: list[ErrorDetail] | None = None) -> JSONResponse:
    body = ErrorResponse(code=code, message=message, details=details)
    return JSONResponse(status_code=code, content=body.model_dump(exclude_none=True))


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ServiceError)
    async def _service_error(_: Request, exc: ServiceError) -> JSONResponse:
        return error_response(exc.status_code, exc.message, exc.details)

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
        details = [
            ErrorDetail(field=str(error["loc"][-1]) if error.get("loc") else "request", reason=error["msg"])
            for error in exc.errors()
        ]
        return error_response(400, InvalidParameter.message, details)

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        return error_response(exc.status_code, str(exc.detail))

    @app.exception_handler(Exception)
    async def _unexpected(_: Request, exc: Exception) -> JSONResponse:
        logger.exception("unexpected error")
        return error_response(500, ServiceError.message)
