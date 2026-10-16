"""Private jobs module: reading postings from the three job-board kinds."""

import json

import httpx

from app.modules.private_jobs import extract
from app.modules.private_jobs.__main__ import build, main
from app.modules.private_jobs.boards import ashby, greenhouse, lever
from app.modules.private_jobs.companies import Board


class TestExperience:
    def test_the_text_beats_the_label(self):
        # "Entry level" in the title, two years in the requirements.
        assert extract.experience("Entry Level Analyst", "You have 2+ years of experience in SQL.") == (
            2,
            None,
            "text",
        )

    def test_ranges_minimums_and_the_real_bar(self):
        assert extract.experience("Engineer", "3-5 years of backend experience") == (3, 5, "text")
        assert extract.experience("Engineer", "Minimum 4 yrs in payments") == (4, None, "text")
        assert extract.experience("SRE", "8+ years overall, including 3+ years of Kubernetes")[0] == 8

    def test_freshers_and_titles(self):
        assert extract.experience("Graduate Engineer Trainee", "Freshers welcome") == (0, 1, "text")
        assert extract.experience("Senior Data Engineer", "Build pipelines.") == (4, None, "title")
        assert extract.experience("Intermediate Backend Engineer", "Ship features.") == (2, None, "title")
        assert extract.experience("Analyst", "Build dashboards.") == (None, None, None)


class TestSkills:
    def test_tech_skills_from_the_text(self):
        found = extract.skills(
            "Backend Engineer", "Python, PostgreSQL and AWS; Kubernetes a plus. Not JavaScript."
        )
        assert {"python", "sql", "aws", "kubernetes", "javascript"} <= set(found)
        assert "java" not in found

    def test_job_functions_only_from_the_title(self):
        boilerplate = "We are an equal opportunity employer. Our marketing and HR teams..."
        assert extract.skills("Backend Engineer", boilerplate) == []
        assert extract.skills("Marketing Manager", boilerplate) == ["marketing"]


def test_india_locations():
    assert extract.in_india("Bengaluru-VTP, India")
    assert extract.in_india("Gurugram")
    assert not extract.in_india("San Francisco, CA", "Remote - US")


GH = Board("greenhouse", "groww", "Groww")
LEVER = Board("lever", "cred", "CRED")
ASHBY = Board("ashby", "atlan", "Atlan")


def test_greenhouse_keeps_india_and_reads_escaped_html():
    data = {
        "jobs": [
            {
                "id": 1,
                "title": "Senior Backend Engineer",
                "location": {"name": "Bengaluru, India"},
                "content": "&lt;p&gt;3+ years with &lt;b&gt;Golang&lt;/b&gt; and Kafka&lt;/p&gt;",
                "absolute_url": "https://job-boards.greenhouse.io/groww/jobs/1",
                "first_published": "2026-10-01T10:00:00Z",
                "departments": [{"name": "Engineering"}],
            },
            {"id": 2, "title": "AE", "location": {"name": "New York"}, "content": ""},
        ]
    }
    [job] = greenhouse(GH, data)
    assert job["id"] == "greenhouse:groww:1"
    assert job["experience_min"] == 3
    assert {"golang", "kafka"} <= set(job["skills"])
    assert job["summary"].startswith("3+ years with Golang")
    assert job["is_agency"] is False


def test_lever_reads_lists_when_description_is_empty():
    data = [
        {
            "id": "a1",
            "text": "accounts payable manager",
            "country": "IN",
            "categories": {"location": "hyderabad", "commitment": "full time", "team": "finance"},
            "descriptionPlain": "",
            "lists": [{"text": "Requirements", "content": "<li>CA with 5+ years</li>"}],
            "hostedUrl": "https://jobs.lever.co/cred/a1",
            "createdAt": 1790573982021,
            "workplaceType": "onsite",
        }
    ]
    [job] = lever(LEVER, data)
    assert job["locations"] == ["Hyderabad"]
    assert job["experience_min"] == 5
    assert "finance" in job["skills"] and "accounting" in job["skills"]
    assert job["posted_at"].startswith("2026-")


def test_ashby_remote_india_and_unlisted():
    data = {
        "jobs": [
            {
                "id": "x",
                "title": "Security Engineer",
                "location": "India",
                "isRemote": True,
                "employmentType": "FullTime",
                "descriptionPlain": "Experience: 2-4 years",
                "jobUrl": "https://jobs.ashbyhq.com/atlan/x",
            },
            {"id": "y", "title": "Hidden", "location": "India", "isListed": False},
        ]
    }
    [job] = ashby(ASHBY, data)
    assert job["remote"] is True and job["employment_type"] == "full_time"
    assert (job["experience_min"], job["experience_max"]) == (2, 4)


def _client(handler):
    return httpx.Client(transport=httpx.MockTransport(handler))


def test_a_board_that_fails_keeps_its_previous_jobs(monkeypatch):
    from app.modules.private_jobs import __main__ as runner

    monkeypatch.setattr(runner, "BOARDS", [GH, LEVER])
    previous = {"jobs": [{"id": "lever:cred:old", "title": "Kept"}]}

    def handler(request: httpx.Request) -> httpx.Response:
        if "lever" in request.url.host:
            return httpx.Response(503)
        return httpx.Response(200, json={"jobs": []})

    result = build(previous, _client(handler))
    assert [j["id"] for j in result["jobs"]] == ["lever:cred:old"]
    assert [s["ok"] for s in result["sources"]] == [True, False]


def test_nothing_reachable_writes_the_previous_file_back(tmp_path, monkeypatch):
    from app.modules.private_jobs import __main__ as runner

    monkeypatch.setattr(runner, "BOARDS", [GH])
    real_client = httpx.Client
    monkeypatch.setattr(
        runner.httpx,
        "Client",
        lambda **_: real_client(transport=httpx.MockTransport(lambda r: httpx.Response(500))),
    )
    prev = tmp_path / "prev.json"
    prev.write_text(json.dumps({"schema": 1, "jobs": [{"id": "greenhouse:groww:9"}], "sources": []}))
    out = tmp_path / "out.json"
    assert main(["--out", str(out), "--previous", str(prev)]) == 0
    assert json.loads(out.read_text())["jobs"] == [{"id": "greenhouse:groww:9"}]
