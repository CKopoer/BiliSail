// Keep branch-push CI useful before a PR exists, without building both refs.
async function shouldRunCi({ github, context, core }) {
  const defaultRef = `refs/heads/${context.payload.repository.default_branch}`;
  if (context.eventName !== 'push' || context.ref === defaultRef) return true;
  const repository = `${context.repo.owner}/${context.repo.repo}`.toLowerCase();
  try {
    const pulls = await github.paginate(github.rest.pulls.list, {
      ...context.repo, state: 'open',
      head: `${context.repo.owner}:${context.ref.replace(/^refs\/heads\//, '')}`,
      per_page: 100,
    });
    return !pulls.some((pull) => pull.head?.repo?.full_name?.toLowerCase() === repository);
  } catch (error) {
    // An unavailable PR API must not suppress the only available CI run.
    core.warning(`Could not check open PRs; running push CI: ${error.message}`);
    return true;
  }
}

module.exports = { shouldRunCi };
