import ballerina/http;
import ballerina/uuid;
import ballerinax/vonage.sms as vs;

public type NewPoliceRequest record {
    string gid;
    string reason;
    string nic;
};

@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"]
    }
}

service /police on new http:Listener(8080) {

    isolated resource function get requests(string status = "", string gid = "", int rlimit = 10000, int offset = 0) returns PoliceRequestWithNIC[]|error? {
        if (status != "" && gid != "") {
            return getRequestsByStatusAndGramaDivision(status, gid, rlimit, offset);
        }
        else if (status != "") {
            return getRequestsByStatus(status, rlimit, offset);
        }
        else if (gid != "") {
            return getRequestsByGramaDivision(gid, rlimit, offset);
        }
        else {
            return getRequests(rlimit, offset);
        }
    }
    isolated resource function get requests/[string id]() returns PoliceRequestWithNIC|error {
        return getRequest(id);
    }
    isolated resource function get requests/nic/[string nic]() returns PoliceRequestWithNIC[]|error?|error {
        Citizen|error citizen = getCitizenByNIC(nic);
        if (citizen is Citizen) {
            return getRequestsForCitizen(citizen.id);
        } else {
            return citizen;
        }
    }

    isolated resource function post requests(NewPoliceRequest request) returns PoliceRequest|error? {
        Citizen|error citizen = getCitizenByNIC(request.nic);
        vs:Client vsClient = check getVsClient();

        if (citizen is error) {
            json latestIdentityRequest = check getLatestIdentityRequest(request.nic);
            Citizen newCitizen = {nic: request.nic, id: uuid:createType4AsString(), fullname: check latestIdentityRequest.fullname, isCriminal: false};
            citizen = addCitizen(newCitizen);
            boolean|error IdentityIsValid = checkCitizenHasValidIdentityRequests(request.nic);
            boolean|error AddressIsValid = checkCitizenHasValidAddressRequests(request.nic);

            PoliceRequest addedrequest = check addRequest(newCitizen, request.reason, request.gid);
            if (IdentityIsValid is error || AddressIsValid is error) {
                _ = check updateRequestStatus(addedrequest.id, "Rejected", newCitizen);
                _ = check sendSms(vsClient, newCitizen, addedrequest);
                addedrequest.status = "Rejected";
                return addedrequest;
            } else if (!IdentityIsValid || !AddressIsValid) {
                _ = check updateRequestStatus(addedrequest.id, "Rejected", newCitizen);
                _ = check sendSms(vsClient, newCitizen, addedrequest);
                addedrequest.status = "Rejected";
                return addedrequest;
            } else {
                _ = check updateRequestStatus(addedrequest.id, "Verified", newCitizen);
                _ = check sendSms(vsClient, newCitizen, addedrequest);
                addedrequest.status = "Verified";
                return addedrequest;
            }
        }
        else {
            PoliceRequest addedrequest = check addRequest(citizen, request.reason, request.gid);
            boolean|error IdentityIsValid = checkCitizenHasValidIdentityRequests(request.nic);
            boolean|error AddressIsValid = checkCitizenHasValidAddressRequests(request.nic);
            boolean|error OffenseExists = checkOffenseExists(citizen.id);

            if (IdentityIsValid is error || AddressIsValid is error || OffenseExists is error) {
                _ = check updateRequestStatus(addedrequest.id, "Rejected", citizen);
                _ = check sendSms(vsClient, citizen, addedrequest);
                addedrequest.status = "Rejected";
            }
            if (!(check IdentityIsValid) || !(check AddressIsValid) || check OffenseExists) {
                _ = check updateRequestStatus(addedrequest.id, "Rejected", citizen);
                _ = check sendSms(vsClient, citizen, addedrequest);
                addedrequest.status = "Rejected";
            }
            else {
                _ = check updateRequestStatus(addedrequest.id, "Verified", citizen);
                _ = check sendSms(vsClient, citizen, addedrequest);
                addedrequest.status = "Verified";
            }
            return addedrequest;
        }
    }
    isolated resource function delete requests/[string id]() returns string|error? {
        error? deleteRequestResult = deleteRequest(id);
        if deleteRequestResult is error {
            return deleteRequestResult;
        }
        else {
            return id;
        }
    }

}
