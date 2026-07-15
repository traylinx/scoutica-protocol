"""
Scoutica Protocol — Reference Python Models

Pydantic models aligned with the Scoutica Protocol JSON schemas.
These models can be used by agents, registry nodes, and tooling
to parse and validate Scoutica Skill Cards programmatically.

Usage:
    from scoutica_models import SkillCard

    card = SkillCard.from_directory("./my-card/")
    print(card.profile.title)
    print(card.rules.remote.policy)
"""

from enum import Enum
import math
from typing import Annotated, Any, List, Literal, Optional, Union

from jsonschema import FormatChecker
from pydantic import (
    AfterValidator,
    BaseModel,
    BeforeValidator,
    ConfigDict,
    Field,
    StrictStr,
    field_validator,
    model_validator,
)


# --- JSON Schema compatibility helpers ---

def _json_integer(value: Any) -> int:
    """Accept exactly the numeric values JSON Schema draft-07 calls integers."""
    if isinstance(value, bool):
        raise ValueError("boolean is not an integer")
    if isinstance(value, int):
        return value
    if isinstance(value, float) and math.isfinite(value) and value.is_integer():
        return int(value)
    raise ValueError("value must be a JSON integer")


JsonInteger = Annotated[int, BeforeValidator(_json_integer)]


_FORMAT_CHECKER = FormatChecker()


def _json_uri(value: str) -> str:
    """Use the same strict URI checker as the authoritative JSON Schema path."""
    # Without the `jsonschema[format]` extra, unknown formats silently pass.
    # Fail closed instead of allowing the Pydantic reference to drift.
    if _FORMAT_CHECKER.conforms("relative/path", "uri"):
        raise ValueError(
            "URI format support unavailable; install jsonschema[format]"
        )
    if not _FORMAT_CHECKER.conforms(value, "uri"):
        raise ValueError("value must be an RFC 3986 URI")
    return value


JsonUri = Annotated[StrictStr, AfterValidator(_json_uri)]
NonEmptyStrictStr = Annotated[StrictStr, Field(min_length=1)]
NonNegativeJsonInteger = Annotated[JsonInteger, Field(ge=0)]
CompensationMinimum = Union[NonNegativeJsonInteger, Literal["negotiable"]]


def _json_array(value: Any) -> Any:
    """Reject Python iterables that are not JSON arrays."""
    if not isinstance(value, list):
        raise ValueError("value must be a JSON array")
    return value


def _json_string(value: Any) -> Any:
    """Reject byte strings and other values Pydantic enums may otherwise coerce."""
    if not isinstance(value, str):
        raise ValueError("value must be a JSON string")
    return value


def _unique(values: List[Any]) -> List[Any]:
    """Implement JSON Schema uniqueItems for scalar arrays."""
    if len(values) != len(set(values)):
        raise ValueError("array items must be unique")
    return values


class CandidateSchemaModel(BaseModel):
    """Shared behavior for models backed by the candidate JSON Schemas."""

    model_config = ConfigDict(extra="forbid")

    def model_dump(self, *args: Any, **kwargs: Any) -> dict[str, Any]:
        """Serialize omitted schema properties as absent rather than explicit nulls."""
        kwargs.setdefault("exclude_none", True)
        return super().model_dump(*args, **kwargs)

    def model_dump_json(self, *args: Any, **kwargs: Any) -> str:
        """JSON serialization counterpart to :meth:`model_dump`."""
        kwargs.setdefault("exclude_none", True)
        return super().model_dump_json(*args, **kwargs)

    @model_validator(mode="before")
    @classmethod
    def reject_explicit_nulls(cls, value: Any) -> Any:
        # The schemas make properties optional by omission; none declare `null` as a type.
        if isinstance(value, dict):
            null_fields = [key for key, item in value.items() if item is None]
            if null_fields:
                raise ValueError(
                    "null is not permitted for: " + ", ".join(sorted(null_fields))
                )
        return value


# --- Profile Models ---

class SeniorityLevel(str, Enum):
    ENTRY = "entry"
    JUNIOR = "junior"
    MID = "mid"
    SENIOR = "senior"
    LEAD = "lead"
    MANAGER = "manager"
    DIRECTOR = "director"
    EXECUTIVE = "executive"


class Availability(str, Enum):
    IMMEDIATELY = "immediately"
    IN_2_WEEKS = "in_2_weeks"
    IN_4_WEEKS = "in_4_weeks"
    IN_8_WEEKS = "in_8_weeks"
    NOT_LOOKING = "not_looking"


class LanguageProficiency(str, Enum):
    NATIVE = "native"
    FLUENT = "fluent"
    PROFESSIONAL = "professional"
    BASIC = "basic"


class SpokenLanguage(CandidateSchemaModel):
    language: StrictStr = Field(..., min_length=1, description="Language name")
    level: LanguageProficiency = Field(..., description="Proficiency level")

    @field_validator("level", mode="before")
    @classmethod
    def require_json_string(cls, value: Any) -> Any:
        return _json_string(value)


class CandidateProfile(CandidateSchemaModel):
    """Matches candidate_profile.schema.json"""
    schema_version: StrictStr = Field(..., pattern=r"^\d+\.\d+\.\d+$")
    name: Optional[StrictStr] = Field(None, min_length=1, description="Professional display name")
    title: StrictStr = Field(..., min_length=1, description="Professional title")
    seniority: SeniorityLevel
    years_experience: Optional[JsonInteger] = Field(None, ge=0)
    availability: Optional[Availability] = None
    primary_domains: List[NonEmptyStrictStr] = Field(..., min_length=1)
    skills: List[NonEmptyStrictStr] = Field(..., min_length=1)
    tools_and_platforms: Optional[List[StrictStr]] = None
    certifications_and_licenses: Optional[List[StrictStr]] = None
    specializations: Optional[List[StrictStr]] = None
    spoken_languages: Optional[List[SpokenLanguage]] = None
    education: Optional[StrictStr] = None
    summary: Optional[StrictStr] = Field(None, max_length=1000)

    @field_validator("seniority", "availability", mode="before")
    @classmethod
    def require_json_enum_strings(cls, value: Any) -> Any:
        return _json_string(value)

    @field_validator(
        "primary_domains",
        "skills",
        "tools_and_platforms",
        "certifications_and_licenses",
        "specializations",
        "spoken_languages",
        mode="before",
    )
    @classmethod
    def require_json_arrays(cls, value: Any) -> Any:
        return _json_array(value)

    @field_validator(
        "primary_domains",
        "skills",
        "tools_and_platforms",
        "certifications_and_licenses",
        "specializations",
    )
    @classmethod
    def require_unique_items(cls, value: List[Any]) -> List[Any]:
        return _unique(value)


# --- Rules of Engagement Models ---

class RemotePolicy(str, Enum):
    REMOTE_ONLY = "remote_only"
    HYBRID = "hybrid"
    FLEXIBLE = "flexible"
    ON_SITE = "on_site"


class EngagementType(str, Enum):
    PERMANENT = "permanent"
    CONTRACT = "contract"
    FRACTIONAL = "fractional"
    ADVISORY = "advisory"
    INTERNSHIP = "internship"


class CompensationMinimums(CandidateSchemaModel):
    permanent: Optional[CompensationMinimum] = Field(
        None, description="Annual salary minimum or 'negotiable'"
    )
    contract: Optional[CompensationMinimum] = Field(
        None, description="Daily rate minimum or 'negotiable'"
    )
    fractional: Optional[CompensationMinimum] = Field(
        None, description="Monthly retainer minimum or 'negotiable'"
    )
    advisory: Optional[CompensationMinimum] = Field(
        None, description="Hourly rate minimum or 'negotiable'"
    )


class Compensation(CandidateSchemaModel):
    minimum_base_eur: Optional[CompensationMinimums] = None


class Engagement(CandidateSchemaModel):
    allowed_types: List[EngagementType] = Field(..., min_length=1)
    compensation: Optional[Compensation] = None

    @field_validator("allowed_types", mode="before")
    @classmethod
    def require_json_array(cls, value: Any) -> Any:
        value = _json_array(value)
        for item in value:
            _json_string(item)
        return value

    @field_validator("allowed_types")
    @classmethod
    def require_unique_items(cls, value: List[EngagementType]) -> List[EngagementType]:
        return _unique(value)


class Remote(CandidateSchemaModel):
    policy: RemotePolicy
    hybrid_locations: Optional[List[StrictStr]] = None

    @field_validator("policy", mode="before")
    @classmethod
    def require_json_string(cls, value: Any) -> Any:
        return _json_string(value)

    @field_validator("hybrid_locations", mode="before")
    @classmethod
    def require_json_array(cls, value: Any) -> Any:
        return _json_array(value)


class StackKeywords(CandidateSchemaModel):
    preferred: Optional[List[StrictStr]] = None

    @field_validator("preferred", mode="before")
    @classmethod
    def require_json_array(cls, value: Any) -> Any:
        return _json_array(value)

    @field_validator("preferred")
    @classmethod
    def require_unique_items(cls, value: List[StrictStr]) -> List[StrictStr]:
        return _unique(value)


class SoftReject(CandidateSchemaModel):
    weak_stack_overlap_below: Optional[JsonInteger] = Field(None, ge=0)


class Filters(CandidateSchemaModel):
    blocked_industries: Optional[List[StrictStr]] = None
    stack_keywords: Optional[StackKeywords] = None
    soft_reject: Optional[SoftReject] = None

    @field_validator("blocked_industries", mode="before")
    @classmethod
    def require_json_array(cls, value: Any) -> Any:
        return _json_array(value)

    @field_validator("blocked_industries")
    @classmethod
    def require_unique_items(cls, value: List[StrictStr]) -> List[StrictStr]:
        return _unique(value)


class Privacy(CandidateSchemaModel):
    zone_1_public: List[StrictStr] = Field(..., description="Fields visible to everyone (free)")
    zone_2_paid: List[StrictStr] = Field(..., description="Fields visible after micro-fee")
    zone_3_private: List[StrictStr] = Field(..., description="Fields shared only after candidate approval")

    @field_validator("zone_1_public", "zone_2_paid", "zone_3_private", mode="before")
    @classmethod
    def require_json_arrays(cls, value: Any) -> Any:
        return _json_array(value)


class RulesOfEngagement(CandidateSchemaModel):
    """Matches roe.schema.json"""
    schema_version: StrictStr = Field(..., pattern=r"^\d+\.\d+\.\d+$")
    engagement: Engagement
    remote: Remote
    filters: Filters
    privacy: Privacy


# --- Evidence Models ---

class EvidenceType(str, Enum):
    GITHUB_REPO = "github_repo"
    WEBSITE = "website"
    PORTFOLIO = "portfolio"
    CERTIFICATE = "certificate"
    ARTICLE = "article"
    REVIEW = "review"
    REFERENCE = "reference"
    PHOTO = "photo"
    VIDEO = "video"
    CASE_STUDY = "case_study"
    PUBLICATION = "publication"
    OTHER = "other"


class EvidenceItem(CandidateSchemaModel):
    type: EvidenceType
    title: StrictStr = Field(..., min_length=1)
    url: JsonUri = Field(..., description="Public URL to the evidence")
    description: StrictStr = Field(..., min_length=1, description="What this proves")
    skills_demonstrated: List[NonEmptyStrictStr] = Field(..., min_length=1)

    @field_validator("type", mode="before")
    @classmethod
    def require_json_string(cls, value: Any) -> Any:
        return _json_string(value)

    @field_validator("skills_demonstrated", mode="before")
    @classmethod
    def require_json_array(cls, value: Any) -> Any:
        return _json_array(value)


class EvidenceRegistry(CandidateSchemaModel):
    """Matches evidence.schema.json"""
    schema_version: StrictStr = Field(..., pattern=r"^\d+\.\d+\.\d+$")
    items: List[EvidenceItem]

    @field_validator("items", mode="before")
    @classmethod
    def require_json_array(cls, value: Any) -> Any:
        return _json_array(value)


# --- Composite Skill Card ---

class SkillCard(CandidateSchemaModel):
    """Complete Scoutica Skill Card combining all three data files."""
    profile: CandidateProfile
    rules: RulesOfEngagement
    evidence: EvidenceRegistry

    @classmethod
    def from_directory(cls, card_dir: str) -> "SkillCard":
        """Load a SkillCard from a directory containing profile.json, rules.yaml, and evidence.json."""
        import json
        from pathlib import Path

        try:
            import yaml
        except ImportError:
            raise ImportError(
                "PyYAML is required: python3 -m pip install 'jsonschema[format]' PyYAML"
            )

        base = Path(card_dir)
        with open(base / "profile.json") as f:
            profile = CandidateProfile(**json.load(f))
        with open(base / "rules.yaml") as f:
            rules = RulesOfEngagement(**yaml.safe_load(f))
        with open(base / "evidence.json") as f:
            evidence = EvidenceRegistry(**json.load(f))

        return cls(profile=profile, rules=rules, evidence=evidence)


# --- Evaluation Models ---

class MatchVerdict(str, Enum):
    ACCEPT = "ACCEPT"
    SOFT_REJECT = "SOFT_REJECT"
    REJECT = "REJECT"


class MatchResult(BaseModel):
    """Output of a capability match evaluation."""
    evaluation_id: str
    candidate_handle: Optional[str] = None
    role_title: str
    match_score: float = Field(..., ge=0.0, le=1.0)
    verdict: MatchVerdict
    matched_capabilities: List[str] = Field(default_factory=list)
    missing_capabilities: List[str] = Field(default_factory=list)
    optional_hits: List[str] = Field(default_factory=list)
    rationale: str
    data_zone_accessed: Literal["zone_1", "zone_2"] = "zone_1"
    human_review_required: bool = True


class PolicyResult(BaseModel):
    """Output of a terms negotiation check."""
    evaluation_id: str
    verdict: MatchVerdict
    reasons: List[str]
    checks_run: List[str] = Field(default_factory=list)
    data_zone_accessed: Literal["zone_1", "zone_2"] = "zone_2"
    human_review_required: bool = True
