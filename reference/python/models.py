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

from pydantic import BaseModel, Field
from typing import Optional, List, Literal, Union
from enum import Enum


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


class SpokenLanguage(BaseModel):
    language: str = Field(..., min_length=1, description="Language name")
    level: LanguageProficiency = Field(..., description="Proficiency level")


class CandidateProfile(BaseModel):
    """Matches candidate_profile.schema.json"""
    schema_version: str = Field(..., pattern=r"^\d+\.\d+\.\d+$")
    name: Optional[str] = Field(None, min_length=1, description="Professional display name")
    title: str = Field(..., min_length=1, description="Professional title")
    seniority: SeniorityLevel
    years_experience: Optional[int] = Field(None, ge=0)
    availability: Optional[Availability] = None
    primary_domains: List[str] = Field(..., min_length=1)
    skills: List[str] = Field(..., min_length=1)
    tools_and_platforms: Optional[List[str]] = None
    certifications_and_licenses: Optional[List[str]] = None
    specializations: Optional[List[str]] = None
    spoken_languages: Optional[List[SpokenLanguage]] = None
    education: Optional[str] = None
    summary: Optional[str] = Field(None, max_length=1000)


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


class CompensationMinimums(BaseModel):
    permanent: Optional[Union[int, str]] = Field(None, description="Annual salary minimum or 'negotiable'")
    contract: Optional[Union[int, str]] = Field(None, description="Daily rate minimum or 'negotiable'")
    fractional: Optional[Union[int, str]] = Field(None, description="Monthly retainer minimum or 'negotiable'")
    advisory: Optional[Union[int, str]] = Field(None, description="Hourly rate minimum or 'negotiable'")


class Compensation(BaseModel):
    minimum_base_eur: Optional[CompensationMinimums] = None


class Engagement(BaseModel):
    allowed_types: List[EngagementType] = Field(..., min_length=1)
    compensation: Optional[Compensation] = None


class Remote(BaseModel):
    policy: RemotePolicy
    hybrid_locations: Optional[List[str]] = None


class StackKeywords(BaseModel):
    preferred: Optional[List[str]] = None


class SoftReject(BaseModel):
    weak_stack_overlap_below: Optional[int] = Field(None, ge=0)


class Filters(BaseModel):
    blocked_industries: Optional[List[str]] = None
    stack_keywords: Optional[StackKeywords] = None
    soft_reject: Optional[SoftReject] = None


class Privacy(BaseModel):
    zone_1_public: List[str] = Field(..., description="Fields visible to everyone (free)")
    zone_2_paid: List[str] = Field(..., description="Fields visible after micro-fee")
    zone_3_private: List[str] = Field(..., description="Fields shared only after candidate approval")


class RulesOfEngagement(BaseModel):
    """Matches roe.schema.json"""
    schema_version: str = Field(..., pattern=r"^\d+\.\d+\.\d+$")
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


class EvidenceItem(BaseModel):
    type: EvidenceType
    title: str = Field(..., min_length=1)
    url: str = Field(..., description="Public URL to the evidence")
    description: str = Field(..., min_length=1, description="What this proves")
    skills_demonstrated: List[str] = Field(..., min_length=1)


class EvidenceRegistry(BaseModel):
    """Matches evidence.schema.json"""
    schema_version: str = Field(..., pattern=r"^\d+\.\d+\.\d+$")
    items: List[EvidenceItem]


# --- Composite Skill Card ---

class SkillCard(BaseModel):
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
            raise ImportError("pyyaml is required: pip install pyyaml")

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
