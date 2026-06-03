import { NextRequest, NextResponse } from 'next/server';

const GIT_PROJECT_ID = process.env.NEXT_PUBLIC_GIT_PROJECT_ID || 'devi698/webtrade';
const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
const [owner, repo] = GIT_PROJECT_ID.split('/');
const CONTENT_PATH = 'trades.json';
const CONTENT_URL = `https://api.github.com/repos/${owner}/${repo}/contents/${CONTENT_PATH}`;
const RAW_URL = `https://raw.githubusercontent.com/${owner}/${repo}/main/${CONTENT_PATH}`;

async function fetchCurrentTrades() {
  console.log('[GIT-TRADE] Fetching from GitHub API instead of raw URL for fresh data');
  const response = await fetch(CONTENT_URL, {
    headers: {
      Authorization: `Bearer ${GITHUB_TOKEN}`,
      Accept: 'application/vnd.github+json',
    },
    cache: 'no-store',
  });
  
  if (response.status === 404) {
    console.log('[GIT-TRADE] File not found, returning empty array');
    return [];
  }
  if (!response.ok) {
    throw new Error(`Unable to load trades.json from GitHub: ${response.statusText}`);
  }

  const data = await response.json();
  const decoded = Buffer.from(data.content, 'base64').toString('utf8');
  return JSON.parse(decoded);
}

export async function GET() {
  try {
    console.log('[GIT-TRADE] GET request - fetching from GitHub API');
    if (!GITHUB_TOKEN) {
      console.error('[GIT-TRADE] GITHUB_TOKEN not set for GET');
      return NextResponse.json([], { status: 200 }); // Return empty array if no token
    }
    const trades = await fetchCurrentTrades();
    return NextResponse.json(trades);
  } catch (error: any) {
    console.error('[GIT-TRADE] GET error:', error);
    return NextResponse.json({ error: error.message || 'Unable to fetch trade signals' }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  console.log('[GIT-TRADE] POST request received');
  console.log('[GIT-TRADE] Token present:', !!GITHUB_TOKEN);
  if (GITHUB_TOKEN) {
    console.log('[GIT-TRADE] Token starts with:', GITHUB_TOKEN.substring(0, 20) + '...');
  }
  
  if (!GITHUB_TOKEN) {
    console.error('[GIT-TRADE] GITHUB_TOKEN not set');
    return NextResponse.json({ error: 'Missing GITHUB_TOKEN environment variable' }, { status: 500 });
  }
  
  console.log('[GIT-TRADE] Token found, repo:', GIT_PROJECT_ID, 'URL:', CONTENT_URL);

  const body = await request.json();
  if (!body?.signals || !Array.isArray(body.signals)) {
    console.error('[GIT-TRADE] Invalid payload');
    return NextResponse.json({ error: 'Invalid payload: signals array is required' }, { status: 400 });
  }

  try {
    console.log('[GIT-TRADE] Fetching existing file from GitHub...');
    const existingResp = await fetch(CONTENT_URL, {
      headers: {
        Authorization: `Bearer ${GITHUB_TOKEN}`,
        Accept: 'application/vnd.github+json',
      },
    });

    console.log('[GIT-TRADE] Existing file response status:', existingResp.status);
    
    let sha: string | undefined;
    let currentSignals: any[] = [];

    if (existingResp.ok) {
      const existingData = await existingResp.json();
      sha = existingData.sha;
      currentSignals = existingData.content
        ? JSON.parse(Buffer.from(existingData.content, 'base64').toString('utf8'))
        : [];
    } else if (existingResp.status !== 404) {
      const errorText = await existingResp.text();
      console.error('[GIT-TRADE] Failed to fetch existing file:', existingResp.status, errorText);
      throw new Error(`Failed to fetch file from GitHub: ${existingResp.status} ${errorText}`);
    }
    // If 404, we create a new file (sha remains undefined)

    const nextSignals = [...currentSignals, ...body.signals];
    const updateBody = {
      message: `Add ${body.signals.length} Git trade signal(s) from app`,
      content: Buffer.from(JSON.stringify(nextSignals, null, 2)).toString('base64'),
      branch: 'main',
    } as any;
    
    // Only add sha if file already exists
    if (sha) {
      updateBody.sha = sha;
    }

    console.log('[GIT-TRADE] Updating file with PUT request...', sha ? '(updating)' : '(creating new)');
    const putResp = await fetch(CONTENT_URL, {
      method: 'PUT',
      headers: {
        Authorization: `Bearer ${GITHUB_TOKEN}`,
        Accept: 'application/vnd.github+json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(updateBody),
    });

    console.log('[GIT-TRADE] PUT response status:', putResp.status);
    
    if (!putResp.ok) {
      const errorText = await putResp.text();
      const scopes = putResp.headers.get('x-oauth-scopes') || putResp.headers.get('X-OAuth-Scopes') || 'unknown';
      const acceptedScopes = putResp.headers.get('x-accepted-oauth-scopes') || putResp.headers.get('X-Accepted-OAuth-Scopes') || 'unknown';
      console.error('[GIT-TRADE] GitHub update failed:', putResp.status, errorText, 'scopes=', scopes, 'accepted=', acceptedScopes);
      const hint = putResp.status === 403
        ? `Check GITHUB_TOKEN permissions: require repo/public_repo or fine-grained Contents write access. Token scopes: ${scopes}. Accepted scopes: ${acceptedScopes}.`
        : '';
      throw new Error(`GitHub update failed: ${putResp.status} ${errorText}${hint ? ' | ' + hint : ''}`);
    }

    console.log('[GIT-TRADE] Success! Updated with', nextSignals.length, 'signals');
    return NextResponse.json({ success: true, count: nextSignals.length });
  } catch (error: any) {
    console.error('[GIT-TRADE] POST error:', error.message);
    return NextResponse.json({ error: error.message || 'Unable to publish trade signals' }, { status: 500 });
  }
}
