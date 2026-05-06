@NamespaceAccessible
public class ExtoleReward {
    public String       rewardId            { get; set; }
    public String       faceValue           { get; set; }
    public String       faceValueType       { get; set; }
    public String       dateEarned          { get; set; }
    public String       state               { get; set; }
    public String       rewardSupplierName  { get; set; }
    public String       program             { get; set; }
    public String       partnerRewardId     { get; set; }
    public List<String> tags                { get; set; }
    public String       createdDate         { get; set; }
    public String       redeemedDate        { get; set; }
    public String       expiryDate          { get; set; }
    public String       journeyName         { get; set; }

    public static ExtoleReward fromMap(Map<String, Object> m) {
        ExtoleReward r = new ExtoleReward();
        r.rewardId           = (String) m.get('id');
        Object fv            = m.get('face_value');
        r.faceValue          = fv == null ? null : String.valueOf(fv);
        r.faceValueType      = (String) m.get('face_value_type');
        r.dateEarned         = (String) m.get('earned_date');
        r.state              = (String) m.get('state');
        r.rewardSupplierName = (String) m.get('reward_supplier_name');
        r.program            = (String) m.get('program');
        r.partnerRewardId    = (String) m.get('partner_reward_id');
        r.createdDate        = (String) m.get('created_date');
        r.redeemedDate       = (String) m.get('redeemed_date');
        r.expiryDate         = (String) m.get('expiry_date');
        r.journeyName        = (String) m.get('journey_name');
        List<Object> rawTags = (List<Object>) m.get('tags');
        if (rawTags != null) {
            r.tags = new List<String>();
            for (Object t : rawTags) {
                r.tags.add((String) t);
            }
        }
        return r;
    }
}
