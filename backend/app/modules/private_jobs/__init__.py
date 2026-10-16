"""Private (corporate) jobs for JobSummit's Private workspace.

Reads the public job boards of direct employers (Greenhouse, Lever, Ashby: JSON
endpoints companies publish for embedding their careers pages) and writes
``private_jobs.json`` for the app, which matches roles on the phone against the
private profile (skills, experience, cities).

Isolated on purpose: it imports nothing from the Govt pipeline and the Govt pipeline
imports nothing from it. It runs as its own workflow step (``ENABLE_PRIVATE_JOBS``
repository variable, on unless set to ``false``) and a failure there never blocks the
Govt data. To remove the feature: delete this folder and that step.

Run: ``python -m app.modules.private_jobs --out ../publish/private_jobs.json``
"""
