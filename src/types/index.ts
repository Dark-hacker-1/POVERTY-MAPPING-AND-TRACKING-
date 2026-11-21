export type Role = 'citizen' | 'volunteer';
export type IssueStatus = 'OPEN'|'CLAIMED'|'IN_PROGRESS'|'AWAITING_CITIZEN_CONFIRMATION'|'RESOLVED'|'DISPUTED'|'REOPENED';
export interface Profile { id:string; full_name:string; role:Role; avatar_url?:string|null; preferred_radius_km?:number|null; preferred_lat?:number|null; preferred_lng?:number|null }
export interface Issue { id:string; issue_code:string; title:string; category:string; description:string; state:string; district:string; city:string; locality:string; address:string|null; latitude:number; longitude:number; urgency:string; status:IssueStatus; created_at:string; reporter_id:string; original_photo_url:string|null; volunteer_count?:number; }
