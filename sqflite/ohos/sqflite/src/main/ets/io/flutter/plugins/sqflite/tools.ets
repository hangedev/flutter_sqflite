export class Tools {
   static stringEndWith(origin:string, endString:string): boolean {
     if (origin.length < endString.length) return false;

     let originEndString:string = '';
     for (let index = 0; index < endString.length; index++) {
       originEndString = originEndString + origin[origin.length - endString.length + index];
     }

     return originEndString == endString;
   }
}

